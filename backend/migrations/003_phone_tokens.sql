-- Upload token of a phone: the background service of the app sends the positions with
-- it, without the session of the user (it survives logouts of other devices and gives
-- access only to the positions of that phone). Only the SHA-256 is stored; a new token
-- replaces the old one.
ALTER TABLE devices ADD COLUMN upload_token_hash bytea UNIQUE;
