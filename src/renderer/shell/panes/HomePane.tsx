import { useEffect, useState } from 'react';
import type { ChannelItem, WeatherReport } from '@msn-aim/shared';
import { useImStore } from '../../stores/imStore';
import { useUiStore } from '../../stores/uiStore';

export function HomePane() {
  const [news, setNews] = useState<ChannelItem[] | null>(null);
  const [weather, setWeather] = useState<WeatherReport | null>(null);
  const accounts = useImStore((s) => s.accounts);
  const activeAccountId = useImStore((s) => s.activeAccountId);
  const setPane = useUiStore((s) => s.setPane);
  const user = accounts.find((a) => a.id === activeAccountId)?.username ?? 'explorer';

  useEffect(() => {
    void window.papillon.invoke('home:getNews', {}).then(setNews).catch(() => setNews([]));
    void window.papillon.invoke('home:getWeather', {}).then(setWeather).catch(() => undefined);
  }, []);

  const openLink = (url: string) => {
    if (!url) return;
    setPane('browser');
    void window.papillon.invoke('browser:navigate', { url });
  };

  const today = new Date().toLocaleDateString(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric'
  });

  return (
    <div className="home">
      <div className="home__masthead">
        <h1>Welcome, {user}!</h1>
        <span>{today}</span>
      </div>
      <div className="home__grid">
        <div className="channel-cell">
          <div className="channel-cell__title">Today's Headlines</div>
          <div className="channel-cell__body">
            {news === null ? (
              <div className="empty-note">Loading headlines…</div>
            ) : news.length === 0 ? (
              <div className="empty-note">Headlines are unavailable right now.</div>
            ) : (
              <ul>
                {news.slice(0, 14).map((item, i) => (
                  <li key={i}>
                    <a onClick={() => openLink(item.link)}>{item.title}</a>
                    <span className="channel-cell__source">{item.source}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
        <div>
          <div className="channel-cell" style={{ marginBottom: 12 }}>
            <div className="channel-cell__title">Weather</div>
            <div className="channel-cell__body">
              {weather ? (
                <div className="weather">
                  <div className="weather__temp">{weather.temperatureC}°C</div>
                  <div>
                    <div className="weather__desc">
                      {weather.description} in {weather.location}
                    </div>
                    <div className="weather__hl">
                      High {weather.highC}° · Low {weather.lowC}°
                    </div>
                  </div>
                </div>
              ) : (
                <div className="empty-note">Weather unavailable.</div>
              )}
            </div>
          </div>
          <div className="channel-cell">
            <div className="channel-cell__title">Explore</div>
            <div className="channel-cell__body">
              <ul>
                <li>
                  <a onClick={() => setPane('chat')}>💬 Chat with your buddies</a>
                </li>
                <li>
                  <a onClick={() => setPane('mail')}>📧 Read your e-mail</a>
                </li>
                <li>
                  <a onClick={() => setPane('media')}>🎵 Play your music</a>
                </li>
                <li>
                  <a onClick={() => openLink('https://web.archive.org/web/2001/http://www.msn.com/')}>
                    🕰️ Visit the web of 2001
                  </a>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
