import { ByteReader, ByteWriter } from '../wire/bytebuf';
import { CLIENT_ONLINE_TOOLS, FOODGROUP_VERSIONS } from '../consts';

/** Parse 01,03 host-online: the list of foodgroups this host serves. */
export function parseHostOnline(body: Buffer): number[] {
  const r = new ByteReader(body);
  const groups: number[] = [];
  while (r.remaining >= 2) groups.push(r.u16());
  return groups;
}

/** Build 01,17 client-versions body. */
export function encodeClientVersions(): Buffer {
  const w = new ByteWriter();
  for (const [fg, ver] of FOODGROUP_VERSIONS) w.u16(fg).u16(ver);
  return w.build();
}

/** Build 01,08 rate-params acknowledgement body. */
export function encodeRateAck(classIds: number[]): Buffer {
  const w = new ByteWriter();
  for (const id of classIds) w.u16(id);
  return w.build();
}

/** Build 01,02 client-online body: foodgroup/version/toolId/toolVersion tuples. */
export function encodeClientOnline(): Buffer {
  const w = new ByteWriter();
  for (const [fg, ver, toolId, toolVer] of CLIENT_ONLINE_TOOLS) {
    w.u16(fg).u16(ver).u16(toolId).u16(toolVer);
  }
  return w.build();
}

/** Build 01,11 idle-notification body (seconds; 0 clears idle). */
export function encodeSetIdle(seconds: number): Buffer {
  return new ByteWriter().u32(seconds).build();
}

/** Parse 01,10 rate-limit warning: code u16 + rate class snapshot. */
export function parseRateWarning(body: Buffer): { code: number; classId: number } {
  const r = new ByteReader(body);
  const code = r.u16();
  const classId = r.remaining >= 2 ? r.u16() : 0;
  return { code, classId };
}
