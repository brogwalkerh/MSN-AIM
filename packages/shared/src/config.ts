export const DEFAULT_OSCAR_HOST = '127.0.0.1';
export const DEFAULT_OSCAR_PORT = 5190;

export const NINA_OSCAR_HOST = 'login.oscar.nina.chat';
export const NINA_OSCAR_PORT = 5190;

export const ESCARGOT_MSNP_HOST = 'm1.escargot.chat';
export const ESCARGOT_MSNP_PORT = 1863;

export interface ServerPreset {
  id: string;
  label: string;
  protocol: 'oscar' | 'msnp';
  host: string;
  port: number;
}

export const SERVER_PRESETS: ServerPreset[] = [
  {
    id: 'local-oscar',
    label: 'Local test server (Open OSCAR Server)',
    protocol: 'oscar',
    host: DEFAULT_OSCAR_HOST,
    port: DEFAULT_OSCAR_PORT
  },
  {
    id: 'nina',
    label: 'NINA public AIM network',
    protocol: 'oscar',
    host: NINA_OSCAR_HOST,
    port: NINA_OSCAR_PORT
  },
  {
    id: 'escargot',
    label: 'Escargot (MSN Messenger — coming soon)',
    protocol: 'msnp',
    host: ESCARGOT_MSNP_HOST,
    port: ESCARGOT_MSNP_PORT
  }
];

export const DEFAULT_NEWS_FEEDS = [
  'https://feeds.bbci.co.uk/news/world/rss.xml',
  'https://hnrss.org/frontpage'
];
