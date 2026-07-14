/** OSCAR foodgroups (service families). */
export const Foodgroup = {
  OSERVICE: 0x0001,
  LOCATE: 0x0002,
  BUDDY: 0x0003,
  ICBM: 0x0004,
  INVITE: 0x0006,
  POPUP: 0x0008,
  PD: 0x0009,
  USER_LOOKUP: 0x000a,
  STATS: 0x000b,
  CHAT_NAV: 0x000d,
  CHAT: 0x000e,
  DIR: 0x000f,
  BART: 0x0010,
  FEEDBAG: 0x0013,
  ICQ: 0x0015,
  BUCP: 0x0017,
  ALERT: 0x0018
} as const;

export const OService = {
  ERROR: 0x0001,
  CLIENT_ONLINE: 0x0002,
  HOST_ONLINE: 0x0003,
  SERVICE_REQUEST: 0x0004,
  SERVICE_RESPONSE: 0x0005,
  RATE_PARAMS_QUERY: 0x0006,
  RATE_PARAMS_REPLY: 0x0007,
  RATE_PARAMS_SUB_ADD: 0x0008,
  RATE_LIMIT_WARNING: 0x000a,
  PAUSE: 0x000b,
  RESUME: 0x000d,
  USER_INFO_QUERY: 0x000e,
  USER_INFO_UPDATE: 0x000f,
  EVIL_NOTIFICATION: 0x0010,
  IDLE_NOTIFICATION: 0x0011,
  MIGRATE: 0x0012,
  MOTD: 0x0013,
  WELL_KNOWN_URLS: 0x0015,
  NOOP: 0x0016,
  CLIENT_VERSIONS: 0x0017,
  HOST_VERSIONS: 0x0018,
  SET_NEARLY_IDLE: 0x001a
} as const;

export const Locate = {
  ERROR: 0x0001,
  RIGHTS_QUERY: 0x0002,
  RIGHTS_REPLY: 0x0003,
  SET_INFO: 0x0004,
  USER_INFO_QUERY: 0x0005,
  USER_INFO_REPLY: 0x0006,
  GET_DIR_INFO: 0x000b,
  USER_INFO_QUERY2: 0x0015
} as const;

export const Buddy = {
  ERROR: 0x0001,
  RIGHTS_QUERY: 0x0002,
  RIGHTS_REPLY: 0x0003,
  ADD_BUDDIES: 0x0004,
  DEL_BUDDIES: 0x0005,
  ARRIVED: 0x000b,
  DEPARTED: 0x000c
} as const;

export const Icbm = {
  ERROR: 0x0001,
  ADD_PARAMETERS: 0x0002,
  PARAMETER_QUERY: 0x0004,
  PARAMETER_REPLY: 0x0005,
  CHANNEL_MSG_TO_HOST: 0x0006,
  CHANNEL_MSG_TO_CLIENT: 0x0007,
  EVIL_REQUEST: 0x0008,
  EVIL_REPLY: 0x0009,
  MISSED_CALLS: 0x000a,
  CLIENT_ERR: 0x000b,
  HOST_ACK: 0x000c,
  OFFLINE_RETRIEVE: 0x0010,
  OFFLINE_DONE: 0x0017,
  MTN: 0x0014
} as const;

export const Feedbag = {
  ERROR: 0x0001,
  RIGHTS_QUERY: 0x0002,
  RIGHTS_REPLY: 0x0003,
  QUERY: 0x0004,
  QUERY_IF_MODIFIED: 0x0005,
  REPLY: 0x0006,
  USE: 0x0007,
  INSERT_ITEM: 0x0008,
  UPDATE_ITEM: 0x0009,
  DELETE_ITEM: 0x000a,
  STATUS: 0x000e,
  REPLY_NOT_MODIFIED: 0x000f,
  START_CLUSTER: 0x0011,
  END_CLUSTER: 0x0012
} as const;

export const Bucp = {
  ERROR: 0x0001,
  LOGIN_REQUEST: 0x0002,
  LOGIN_RESPONSE: 0x0003,
  CHALLENGE_REQUEST: 0x0006,
  CHALLENGE_RESPONSE: 0x0007
} as const;

/** Feedbag (SSI) item classes. */
export const FeedbagClass = {
  BUDDY: 0x0000,
  GROUP: 0x0001,
  PERMIT: 0x0002,
  DENY: 0x0003,
  PD_INFO: 0x0004,
  PRESENCE: 0x0005,
  BUDDY_ICON: 0x0014
} as const;

/** User class bit flags (TLV 0x01 in userinfo blocks). */
export const UserClass = {
  UNCONFIRMED: 0x0001,
  ADMINISTRATOR: 0x0002,
  AOL: 0x0004,
  COMMERCIAL: 0x0008,
  FREE: 0x0010,
  AWAY: 0x0020,
  ICQ: 0x0040,
  WIRELESS: 0x0080
} as const;

/** BUCP login error codes (TLV 0x08 of SNAC 17,03). */
export const AuthErrorCode: Record<number, string> = {
  0x0001: 'Invalid screen name or password',
  0x0004: 'Incorrect screen name or password',
  0x0005: 'Mismatched screen name or password',
  0x0007: 'Invalid account',
  0x0008: 'Deleted account',
  0x0011: 'Suspended account',
  0x0018: 'Connecting too frequently — wait a few minutes and try again',
  0x001c: 'Client version too old',
  0x001d: 'Rate limit: reconnecting too frequently'
};

/** Client identity presented at login (an original ID string, not AOL's). */
export const CLIENT_ID_STRING = 'Papillon MSN-AIM client';
export const CLIENT_ID = 0x0109; // matches AIM 5.x family so servers accept us
export const CLIENT_MAJOR = 5;
export const CLIENT_MINOR = 1;
export const CLIENT_LESSER = 0;
export const CLIENT_BUILD = 3036;
export const CLIENT_DISTRIBUTION = 0;
export const CLIENT_LANGUAGE = 'en';
export const CLIENT_COUNTRY = 'us';

export const AIM_MD5_STRING = 'AOL Instant Messenger (SM)';

/** Foodgroup versions announced in 01,17 / used in client-online 01,02. */
export const FOODGROUP_VERSIONS: ReadonlyArray<readonly [number, number]> = [
  [Foodgroup.OSERVICE, 4],
  [Foodgroup.LOCATE, 1],
  [Foodgroup.BUDDY, 1],
  [Foodgroup.ICBM, 1],
  [Foodgroup.PD, 1],
  [Foodgroup.FEEDBAG, 4]
];

/** toolId/toolVersion tuples for client-online (mirrors AIM 5.x). */
export const CLIENT_ONLINE_TOOLS: ReadonlyArray<readonly [number, number, number, number]> =
  FOODGROUP_VERSIONS.map(([fg, ver]) => [fg, ver, 0x0110, 0x0629] as const);
