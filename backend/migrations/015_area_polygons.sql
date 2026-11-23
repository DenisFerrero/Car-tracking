-- Arrival areas drawn as a polygon ([[lat, lon], ...], 3-50 vertices) instead of a circle:
-- lat, lon and radius are then its center and the circle around it (map, list)
ALTER TABLE geofences ADD COLUMN polygon jsonb;
