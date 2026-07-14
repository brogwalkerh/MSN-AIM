import type { ImProtocolClient } from './ImProtocolClient';
import type { ProtocolId } from './types';

export type ProtocolClientFactory = () => ImProtocolClient;

const factories = new Map<ProtocolId, ProtocolClientFactory>();

export function registerProtocol(id: ProtocolId, factory: ProtocolClientFactory): void {
  factories.set(id, factory);
}

export function createProtocolClient(id: ProtocolId): ImProtocolClient {
  const factory = factories.get(id);
  if (!factory) throw new Error(`No protocol registered for '${id}'`);
  return factory();
}

export function registeredProtocols(): ProtocolId[] {
  return [...factories.keys()];
}
