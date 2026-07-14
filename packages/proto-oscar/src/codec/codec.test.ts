import { describe, expect, it } from 'vitest';
import { Charset, decodeText, encodeText } from './charset';
import { decodeMessageBlock, encodeMessageBlock } from './icbm-message';
import { htmlToPlainText, sanitizeAimHtml } from './html';
import { bucpPasswordHash } from '../auth/md5login';
import { roastPassword } from '../auth/roast';

describe('charset codec', () => {
  it('uses ASCII for 7-bit clean text', () => {
    const { charset, buffer } = encodeText('hello world');
    expect(charset).toBe(Charset.ASCII);
    expect(decodeText(charset, buffer)).toBe('hello world');
  });

  it('uses ISO-8859-1 for accented latin text', () => {
    const text = 'café au lait — non merci: àéîöü';
    const { charset, buffer } = encodeText('café àéîöü');
    expect(charset).toBe(Charset.LATIN1);
    expect(decodeText(charset, buffer)).toBe('café àéîöü');
    void text;
  });

  it('uses UCS-2BE for non-latin text and preserves surrogate pairs (emoji)', () => {
    const text = 'héllo 👋 世界 — Ω';
    const { charset, buffer } = encodeText(text);
    expect(charset).toBe(Charset.UCS2BE);
    expect(decodeText(charset, buffer)).toBe(text);
    // Verify actual big-endian layout: 'h' = 0x0068.
    expect(buffer.readUInt16BE(0)).toBe('h'.charCodeAt(0));
  });

  it('tolerates truncated UCS-2 payloads', () => {
    const { buffer } = encodeText('ab©');
    expect(() => decodeText(Charset.UCS2BE, buffer.subarray(0, buffer.length - 1))).not.toThrow();
  });
});

describe('ICBM message block', () => {
  it('round-trips ascii, latin1 and unicode text', () => {
    for (const text of ['plain text', 'crème brûlée', 'unicode 🙂 テスト', '<b>bold</b> html']) {
      expect(decodeMessageBlock(encodeMessageBlock(text))).toBe(text);
    }
  });

  it('decodes a hand-built classic-AIM fragment layout', () => {
    // fragment 5 (features 01 01 01 02) + fragment 1 with ascii "hey"
    const block = Buffer.from([
      0x05, 0x01, 0x00, 0x04, 0x01, 0x01, 0x01, 0x02,
      0x01, 0x01, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x68, 0x65, 0x79
    ]);
    expect(decodeMessageBlock(block)).toBe('hey');
  });
});

describe('AIM HTML sanitizer', () => {
  it('keeps the classic AIM formatting subset', () => {
    const input = '<B>bold</B> <i>it</i> <u>u</u> <font color="#ff0000" size="4">red</font><br>';
    expect(sanitizeAimHtml(input)).toBe(
      '<b>bold</b> <i>it</i> <u>u</u> <font color="#ff0000" size="4">red</font><br/>'
    );
  });

  it('strips scripts and event handlers', () => {
    expect(sanitizeAimHtml('<script>alert(1)</script>hi')).toBe('alert(1)hi');
    expect(sanitizeAimHtml('<a href="javascript:evil()">x</a>')).toBe('<a href="#">x</a>');
    expect(sanitizeAimHtml('<b onclick="evil()">x</b>')).toBe('<b>x</b>');
  });

  it('escapes raw angle brackets in text', () => {
    expect(sanitizeAimHtml('1 < 2 & 3 > 2')).toBe('1 &lt; 2 &amp; 3 &gt; 2');
  });

  it('drops html/body wrappers from classic clients', () => {
    expect(sanitizeAimHtml('<HTML><BODY>hello</BODY></HTML>')).toBe('hello');
  });

  it('converts to plain text', () => {
    expect(htmlToPlainText('<b>hi</b><br>there')).toBe('hi\nthere');
  });
});

describe('BUCP password hash', () => {
  it('matches the known-answer vector', () => {
    // md5("1234567890" + "S3cret!" + "AOL Instant Messenger (SM)")
    expect(bucpPasswordHash(Buffer.from('1234567890'), 'S3cret!').toString('hex')).toBe(
      '8ba9311bd09f189cc208d08efd6dd3c3'
    );
  });
});

describe('legacy roast', () => {
  it('XORs with the classic table', () => {
    // 'p'(0x70)^0xf3=0x83, 'a'(0x61)^0x26=0x47, 's'(0x73)^0x81=0xf2, 's'(0x73)^0xc4=0xb7
    expect(roastPassword('pass').toString('hex')).toBe('8347f2b7');
  });
});
