CREATE TABLE IF NOT EXISTS t_multi (
    id   INTEGER PRIMARY KEY,
    note TEXT
);

INSERT INTO t_multi (note) VALUES ('first');
INSERT INTO t_multi (note) VALUES ('second');
