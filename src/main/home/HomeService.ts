import Parser from 'rss-parser';
import { DEFAULT_NEWS_FEEDS, createLogger, type ChannelItem, type WeatherReport } from '@msn-aim/shared';
import { handle } from '../ipc/typed-ipc';
import { JsonStore } from '../storage/JsonStore';

const log = createLogger('home');
const CACHE_TTL_MS = 15 * 60 * 1000;

const WEATHER_DESCRIPTIONS: Record<number, string> = {
  0: 'Clear skies',
  1: 'Mostly clear',
  2: 'Partly cloudy',
  3: 'Overcast',
  45: 'Fog',
  48: 'Freezing fog',
  51: 'Light drizzle',
  61: 'Light rain',
  63: 'Rain',
  65: 'Heavy rain',
  71: 'Light snow',
  73: 'Snow',
  75: 'Heavy snow',
  80: 'Showers',
  95: 'Thunderstorms'
};

/** Home-pane content: RSS headlines + open-meteo weather, cached in main. */
export class HomeService {
  private settings = new JsonStore<{ feeds: string[]; location: string }>('home', {
    feeds: DEFAULT_NEWS_FEEDS,
    location: 'Seattle'
  });
  private newsCache: { at: number; items: ChannelItem[] } | null = null;
  private weatherCache: { at: number; report: WeatherReport | null } | null = null;

  registerIpc(): void {
    handle('home:getNews', async () => {
      if (this.newsCache && Date.now() - this.newsCache.at < CACHE_TTL_MS) {
        return this.newsCache.items;
      }
      const parser = new Parser({ timeout: 10_000 });
      const items: ChannelItem[] = [];
      await Promise.allSettled(
        this.settings.get('feeds').map(async (url) => {
          try {
            const feed = await parser.parseURL(url);
            for (const item of feed.items.slice(0, 8)) {
              items.push({
                title: item.title ?? '(untitled)',
                link: item.link ?? '',
                source: feed.title ?? url,
                publishedEpochMs: item.isoDate ? new Date(item.isoDate).getTime() : undefined
              });
            }
          } catch (err) {
            log.warn(`feed failed ${url}: ${(err as Error).message}`);
          }
        })
      );
      items.sort((a, b) => (b.publishedEpochMs ?? 0) - (a.publishedEpochMs ?? 0));
      this.newsCache = { at: Date.now(), items };
      return items;
    });

    handle('home:getWeather', async ({ location }) => {
      if (location) this.settings.set('location', location);
      const where = location || this.settings.get('location');
      if (!location && this.weatherCache && Date.now() - this.weatherCache.at < CACHE_TTL_MS) {
        return this.weatherCache.report;
      }
      try {
        const geo = (await (
          await fetch(
            `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(where)}&count=1`
          )
        ).json()) as { results?: { latitude: number; longitude: number; name: string }[] };
        const place = geo.results?.[0];
        if (!place) return null;
        const wx = (await (
          await fetch(
            `https://api.open-meteo.com/v1/forecast?latitude=${place.latitude}&longitude=${place.longitude}` +
              `&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto`
          )
        ).json()) as {
          current?: { temperature_2m: number; weather_code: number };
          daily?: { temperature_2m_max: number[]; temperature_2m_min: number[] };
        };
        if (!wx.current) return null;
        const report: WeatherReport = {
          location: place.name,
          temperatureC: Math.round(wx.current.temperature_2m),
          weatherCode: wx.current.weather_code,
          description: WEATHER_DESCRIPTIONS[wx.current.weather_code] ?? 'Weather',
          highC: Math.round(wx.daily?.temperature_2m_max?.[0] ?? wx.current.temperature_2m),
          lowC: Math.round(wx.daily?.temperature_2m_min?.[0] ?? wx.current.temperature_2m)
        };
        this.weatherCache = { at: Date.now(), report };
        return report;
      } catch (err) {
        log.warn(`weather failed: ${(err as Error).message}`);
        return this.weatherCache?.report ?? null;
      }
    });
  }
}
