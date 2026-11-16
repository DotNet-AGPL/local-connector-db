DROP DATABASE IF EXISTS lcdb;
CREATE DATABASE lcdb CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE lcdb;

-- 全类型覆盖。刻意把 TINYINT(1) 放进 0 / 1 / 2 三种值，用于验证驱动到 bool 的映射行为。
CREATE TABLE t_types (
    id        INT PRIMARY KEY,
    ti1       TINYINT(1),
    ti2       TINYINT(2),
    si        SMALLINT,
    mi        MEDIUMINT,
    i         INT,
    bi        BIGINT,
    ubi       BIGINT UNSIGNED,
    de        DECIMAL(12,3),
    fl        FLOAT,
    db        DOUBLE,
    dt        DATETIME,
    ts        TIMESTAMP NULL,
    da        DATE,
    tm        TIME,
    bl        BLOB,
    tx        TEXT,
    en        ENUM('alpha','beta','gamma'),
    js        JSON,
    bt1       BIT(1),
    bt8       BIT(8)
);

INSERT INTO t_types
    (id, ti1, ti2, si, mi, i, bi, ubi, de, fl, db, dt, ts, da, tm, bl, tx, en, js, bt1, bt8)
VALUES
    (1, 1, 42, 1000, 100000, 123456789, 9007199254740993, 18446744073709551615,
     1234.500, 1.5, 2.25,
     '2026-11-13 10:00:00', '2026-11-13 10:00:00', '2026-11-13', '10:30:00',
     X'0102030405', 'hello', 'beta', '{"k": 1, "arr": [1, 2]}', b'1', b'11111111'),
    (2, 0, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL,
     NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL, NULL),
    (3, 2, NULL, NULL, NULL, NULL, NULL, NULL,
     NULL, NULL, NULL,
     NULL, NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL, NULL);

CREATE TABLE t_cn (
    id      INT PRIMARY KEY,
    name_cn VARCHAR(64)
);

INSERT INTO t_cn (id, name_cn) VALUES (1, '张三');
INSERT INTO t_cn (id, name_cn) VALUES (2, '李四（测试）');
INSERT INTO t_cn (id, name_cn) VALUES (3, 'emoji 😀 测试');

CREATE TABLE t_parent (id INT PRIMARY KEY);
CREATE TABLE t_child (
    id        INT PRIMARY KEY AUTO_INCREMENT,
    parent_id INT,
    CONSTRAINT fk_child_parent FOREIGN KEY (parent_id) REFERENCES t_parent (id)
);

INSERT INTO t_parent (id) VALUES (1);
INSERT INTO t_child (parent_id) VALUES (1);

-- DML 用例用表：AUTO_INCREMENT 显式从 1 开始，保证 insertId 可预期
CREATE TABLE t_items (
    id     INT PRIMARY KEY AUTO_INCREMENT,
    name   VARCHAR(32) NOT NULL,
    qty    INT,
    amount DECIMAL(10,2)
) AUTO_INCREMENT = 1;

INSERT INTO t_items (name, qty, amount) VALUES ('alpha', 10, 1.50);
INSERT INTO t_items (name, qty, amount) VALUES ('beta', 20, 2.25);
INSERT INTO t_items (name, qty, amount) VALUES ('gamma', -5, NULL);
