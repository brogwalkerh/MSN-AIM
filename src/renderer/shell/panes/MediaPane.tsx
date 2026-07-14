import { useEffect, useRef, useState } from 'react';
import type { TrackInfo } from '@msn-aim/shared';

function formatTime(sec: number): string {
  if (!isFinite(sec)) return '--:--';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export function MediaPane() {
  const audioRef = useRef<HTMLAudioElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const [playlist, setPlaylist] = useState<TrackInfo[]>([]);
  const [current, setCurrent] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [streamUrl, setStreamUrl] = useState('');

  const track = playlist[current];

  // Visualizer: classic green bars.
  useEffect(() => {
    const audio = audioRef.current;
    const canvas = canvasRef.current;
    if (!audio || !canvas) return;
    let raf = 0;
    const ctx = canvas.getContext('2d');
    const ensureAnalyser = () => {
      if (analyserRef.current) return analyserRef.current;
      const ac = new AudioContext();
      const source = ac.createMediaElementSource(audio);
      const analyser = ac.createAnalyser();
      analyser.fftSize = 64;
      source.connect(analyser);
      analyser.connect(ac.destination);
      analyserRef.current = analyser;
      return analyser;
    };
    const draw = () => {
      raf = requestAnimationFrame(draw);
      if (!ctx) return;
      const analyser = analyserRef.current;
      ctx.fillStyle = '#041018';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      if (!analyser) return;
      const data = new Uint8Array(analyser.frequencyBinCount);
      analyser.getByteFrequencyData(data);
      const barWidth = canvas.width / data.length;
      for (let i = 0; i < data.length; i++) {
        const h = ((data[i] ?? 0) / 255) * canvas.height;
        ctx.fillStyle = h > canvas.height * 0.75 ? '#ff5a4d' : '#4dff6a';
        ctx.fillRect(i * barWidth + 1, canvas.height - h, barWidth - 2, h);
      }
    };
    const onPlay = () => {
      ensureAnalyser();
      draw();
    };
    audio.addEventListener('play', onPlay);
    return () => {
      audio.removeEventListener('play', onPlay);
      cancelAnimationFrame(raf);
    };
  }, []);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    const onTime = () => setPosition(audio.currentTime);
    const onDuration = () => setDuration(audio.duration || 0);
    const onEnded = () => next();
    const onPlayState = () => setPlaying(!audio.paused);
    audio.addEventListener('timeupdate', onTime);
    audio.addEventListener('durationchange', onDuration);
    audio.addEventListener('ended', onEnded);
    audio.addEventListener('play', onPlayState);
    audio.addEventListener('pause', onPlayState);
    return () => {
      audio.removeEventListener('timeupdate', onTime);
      audio.removeEventListener('durationchange', onDuration);
      audio.removeEventListener('ended', onEnded);
      audio.removeEventListener('play', onPlayState);
      audio.removeEventListener('pause', onPlayState);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playlist, current]);

  const playIndex = (index: number) => {
    const audio = audioRef.current;
    const t = playlist[index];
    if (!audio || !t) return;
    setCurrent(index);
    audio.src = t.url;
    void audio.play().catch(() => setPlaying(false));
  };

  const toggle = () => {
    const audio = audioRef.current;
    if (!audio) return;
    if (audio.paused) {
      if (!audio.src && track) playIndex(current);
      else void audio.play();
    } else audio.pause();
  };

  const next = () => playlist.length > 0 && playIndex((current + 1) % playlist.length);
  const prev = () => playlist.length > 0 && playIndex((current - 1 + playlist.length) % playlist.length);

  const addFiles = () => {
    void window.papillon.invoke('media:openFiles', {}).then((tracks) => {
      if (tracks.length === 0) return;
      setPlaylist((p) => {
        const merged = [...p, ...tracks];
        if (p.length === 0) setTimeout(() => playIndex(0), 0);
        return merged;
      });
    });
  };

  const addStream = () => {
    if (!streamUrl.trim()) return;
    void window.papillon.invoke('media:addStream', { url: streamUrl.trim() }).then((t) => {
      setPlaylist((p) => [...p, t]);
      setStreamUrl('');
    });
  };

  return (
    <div className="media">
      <audio ref={audioRef} crossOrigin="anonymous" />
      <div className="media__deck">
        <div className="media__lcd">
          <div>{track ? track.title : 'MSN Music — no track loaded'}</div>
          <div>
            {formatTime(position)} / {formatTime(duration)} {playing ? '▶ PLAYING' : '❚❚ STOPPED'}
          </div>
        </div>
        <canvas ref={canvasRef} className="media__viz" width={430} height={56} />
        <div className="media__transport">
          <button className="media__knob" onClick={prev} aria-label="Previous">
            ⏮
          </button>
          <button className="media__knob media__knob--big" onClick={toggle} aria-label="Play/Pause">
            {playing ? '❚❚' : '▶'}
          </button>
          <button className="media__knob" onClick={next} aria-label="Next">
            ⏭
          </button>
          <input
            className="media__slider"
            type="range"
            min={0}
            max={duration || 0}
            step={0.5}
            value={position}
            onChange={(e) => {
              const audio = audioRef.current;
              if (audio) audio.currentTime = parseFloat(e.target.value);
            }}
          />
        </div>
        <div className="signin__row">
          <button className="btn" onClick={addFiles}>
            ＋ Add music files
          </button>
          <input
            style={{ flex: 1, padding: '0 6px', border: '1px solid var(--msn-blue-light)', borderRadius: 4 }}
            placeholder="Internet radio URL (http://…)"
            value={streamUrl}
            onChange={(e) => setStreamUrl(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && addStream()}
          />
        </div>
      </div>
      <div className="media__playlist">
        {playlist.length === 0 ? (
          <div className="empty-note">Your playlist is empty — add some music!</div>
        ) : (
          playlist.map((t, i) => (
            <button
              key={t.id}
              className={`media__track ${i === current ? 'media__track--active' : ''}`}
              onDoubleClick={() => playIndex(i)}
            >
              {i + 1}. {t.title}
              {t.artist ? ` — ${t.artist}` : ''}
            </button>
          ))
        )}
      </div>
    </div>
  );
}
