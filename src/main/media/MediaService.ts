import { basename, extname } from 'node:path';
import { createReadStream, statSync } from 'node:fs';
import { Readable } from 'node:stream';
import { dialog, protocol } from 'electron';
import { randomUUID } from 'node:crypto';
import type { TrackInfo } from '@msn-aim/shared';
import { handle } from '../ipc/typed-ipc';

const AUDIO_EXTENSIONS = ['mp3', 'ogg', 'oga', 'wav', 'flac', 'm4a', 'aac', 'opus', 'webm'];
const MIME_BY_EXT: Record<string, string> = {
  '.mp3': 'audio/mpeg',
  '.ogg': 'audio/ogg',
  '.oga': 'audio/ogg',
  '.wav': 'audio/wav',
  '.flac': 'audio/flac',
  '.m4a': 'audio/mp4',
  '.aac': 'audio/aac',
  '.opus': 'audio/ogg',
  '.webm': 'audio/webm'
};

/**
 * Media pane backend. User-picked files are exposed to the sandboxed
 * renderer through a media:// protocol keyed by opaque ids — the renderer
 * never sees or requests raw filesystem paths.
 */
export class MediaService {
  private readonly files = new Map<string, string>(); // id -> absolute path

  static registerScheme(): void {
    protocol.registerSchemesAsPrivileged([
      { scheme: 'media', privileges: { stream: true, supportFetchAPI: true } }
    ]);
  }

  attachProtocolHandler(): void {
    protocol.handle('media', (request) => {
      const id = new URL(request.url).hostname;
      const path = this.files.get(id);
      if (!path) return new Response('not found', { status: 404 });
      const mime = MIME_BY_EXT[extname(path).toLowerCase()] ?? 'application/octet-stream';
      const size = statSync(path).size;
      const range = request.headers.get('range');
      if (range) {
        const match = /bytes=(\d+)-(\d*)/.exec(range);
        const start = match ? parseInt(match[1]!, 10) : 0;
        const end = match?.[2] ? parseInt(match[2], 10) : size - 1;
        const stream = Readable.toWeb(
          createReadStream(path, { start, end })
        ) as unknown as ReadableStream;
        return new Response(stream, {
          status: 206,
          headers: {
            'content-type': mime,
            'content-range': `bytes ${start}-${end}/${size}`,
            'content-length': String(end - start + 1),
            'accept-ranges': 'bytes'
          }
        });
      }
      const stream = Readable.toWeb(createReadStream(path)) as unknown as ReadableStream;
      return new Response(stream, {
        headers: { 'content-type': mime, 'content-length': String(size), 'accept-ranges': 'bytes' }
      });
    });
  }

  registerIpc(): void {
    handle('media:openFiles', async () => {
      const result = await dialog.showOpenDialog({
        title: 'Add music to My Music',
        properties: ['openFile', 'multiSelections'],
        filters: [{ name: 'Audio', extensions: AUDIO_EXTENSIONS }]
      });
      const tracks: TrackInfo[] = [];
      for (const path of result.filePaths) {
        const id = randomUUID();
        this.files.set(id, path);
        tracks.push({
          id,
          title: basename(path, extname(path)),
          artist: '',
          album: '',
          durationSec: 0,
          url: `media://${id}/`
        });
      }
      return tracks;
    });

    handle('media:addStream', async ({ url }) => {
      if (!/^https?:\/\//i.test(url)) throw new Error('Stream URL must be http(s)');
      return {
        id: randomUUID(),
        title: url.replace(/^https?:\/\//, ''),
        artist: 'Internet radio',
        album: '',
        durationSec: 0,
        url
      };
    });
  }
}
