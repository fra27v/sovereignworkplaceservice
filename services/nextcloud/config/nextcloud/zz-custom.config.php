<?php
$CONFIG = [
  // UX pulita
  'defaultapp' => 'files',
  'knowledgebaseenabled' => false,
  'simpleSignUpLink.shown' => false,

  'skeletondirectory' => '/var/www/html/skeleton',

  'default_quota' => '5 GB',

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

  'oidc_login_provider_url' => 'https://auth.internal/realms/sovereign',
  'oidc_login_client_id' => trim(file_get_contents('/secrets/oidc_client_id')),
  'oidc_login_client_secret' => trim(file_get_contents('/secrets/oidc_client_secret')),

  'oidc_login_auto_redirect' => true,
  'oidc_login_logout_url' => 'https://auth.internal/realms/sovereign/protocol/openid-connect/logout',
  'oidc_login_disable_registration' => false,

  'oidc_login_attributes' => [
    'id' => 'sub',
    'name' => 'name',
    'mail' => 'email',
    'groups' => 'nextcloud_groups',
  ],

  'auth.bruteforce.protection.enabled' => true,
  'ratelimit.protection.enabled' => true,
];