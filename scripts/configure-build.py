import base64
import os
import plistlib
import sys
from urllib.parse import urlparse

path = sys.argv[1]
with open(path, 'rb') as stream:
    info = plistlib.load(stream)
feed = os.environ.get('UPDATE_FEED_URL', '')
public_key = os.environ.get('SPARKLE_PUBLIC_KEY', '')
if bool(feed) != bool(public_key):
    sys.exit('UPDATE_FEED_URL and SPARKLE_PUBLIC_KEY must be set together')
if feed:
    if urlparse(feed).scheme != 'https' or not urlparse(feed).netloc:
        sys.exit('UPDATE_FEED_URL must be an HTTPS URL')
    try:
        if len(base64.b64decode(public_key, validate=True)) != 32:
            raise ValueError()
    except ValueError:
        sys.exit("SPARKLE_PUBLIC_KEY must be a base64-encoded 32-byte Ed25519 public key")
    info.update(SUFeedURL=feed, SUPublicEDKey=public_key)
for variable, key in [('APP_VERSION', 'CFBundleShortVersionString'),
                      ('APP_BUILD', 'CFBundleVersion'), ('APTABASE_APP_KEY', 'AptabaseAppKey')]:
    if os.environ.get(variable):
        info[key] = os.environ[variable]
info['ClipStackReleaseBuild'] = os.environ.get('RELEASE_BUILD') == '1'
with open(path, 'wb') as stream:
    plistlib.dump(info, stream)
