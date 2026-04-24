<?php
$CONFIG = [
  'trusted_domains' =>
  [
    'files.internal',
  ],

  'trusted_proxies' =>
  [
    '172.18.0.0/16',
  ],

  'overwrite.cli.url' => 'https://files.internal',
  'overwritehost' => 'files.internal',
  'overwriteprotocol' => 'https',

  'default_phone_region' => 'FR',
  'default_locale' => 'it_IT',
  'logtimezone' => 'Europe/Paris',

  'memcache.local' => '\OC\Memcache\APCu',
  'memcache.distributed' => '\OC\Memcache\Redis',
  'memcache.locking' => '\OC\Memcache\Redis',

  'redis' => [
    'host' => 'nextcloud-redis',
    'port' => 6379,
    'password' => trim(@file_get_contents('/secrets/redis_password')),
    'timeout' => 1.5,
  ],

  'forwarded_for_headers' => ['HTTP_X_FORWARDED_FOR'],
  'maintenance_window_start' => 1,
];