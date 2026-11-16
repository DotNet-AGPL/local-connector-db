DROP TABLE IF EXISTS t_items;
CREATE TABLE t_items (
    id     INTEGER PRIMARY KEY,
    name   TEXT NOT NULL,
    qty    INTEGER,
    amount REAL,
    payload BLOB
);

INSERT INTO t_items (name, qty, amount, payload) VALUES ('alpha', 10, 1.5, X'0102030405');
INSERT INTO t_items (name, qty, amount, payload) VALUES ('beta', 20, 2.25, NULL);
INSERT INTO t_items (name, qty, amount) VALUES ('gamma', -5, NULL);

DROP TABLE IF EXISTS t_cn;
CREATE TABLE t_cn (
    id      INTEGER PRIMARY KEY,
    name_cn TEXT
);

INSERT INTO t_cn (name_cn) VALUES ('张三');
INSERT INTO t_cn (name_cn) VALUES ('李四（测试）');
INSERT INTO t_cn (name_cn) VALUES ('emoji 😀 测试');

DROP TABLE IF EXISTS t_big;
CREATE TABLE t_big (
    id  INTEGER PRIMARY KEY,
    big INTEGER
);

INSERT INTO t_big (big) VALUES (9007199254740993);
INSERT INTO t_big (big) VALUES (1234567890123456789);

DROP TABLE IF EXISTS t_child;
DROP TABLE IF EXISTS t_parent;
CREATE TABLE t_parent (id INTEGER PRIMARY KEY);
CREATE TABLE t_child (
    id        INTEGER PRIMARY KEY,
    parent_id INTEGER REFERENCES t_parent (id)
);

INSERT INTO t_parent (id) VALUES (1);
INSERT INTO t_child (parent_id) VALUES (1);
