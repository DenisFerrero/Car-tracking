-- Extra data of the trackers compressed after a month like the traffic: JSON objects of the
-- same keys every few seconds, they shrink well (segments by device, ordered by time)
ALTER TABLE device_extra SET (timescaledb.compress, timescaledb.compress_segmentby = 'device_id', timescaledb.compress_orderby = 'time');
SELECT add_compression_policy('device_extra', interval '30 days');
