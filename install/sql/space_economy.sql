CREATE TABLE IF NOT EXISTS `space_economy` (
  `id` INT NOT NULL PRIMARY KEY,
  `vault` BIGINT NOT NULL DEFAULT 0,
  `inflation` FLOAT NOT NULL DEFAULT 1.0
);

INSERT INTO `space_economy` (`id`, `vault`, `inflation`) VALUES (1, 0, 1.0)
  ON DUPLICATE KEY UPDATE id = id;

CREATE TABLE IF NOT EXISTS `space_economy_debts` (
  `citizenid` VARCHAR(50) NOT NULL PRIMARY KEY,
  `amount` BIGINT NOT NULL,
  `reason` VARCHAR(255) DEFAULT NULL
);


CREATE TABLE IF NOT EXISTS `space_economy_logs` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `timestamp` TIMESTAMP NOT NULL DEFAULT current_timestamp(),
  `category` VARCHAR(50) NOT NULL,
  `message` TEXT NOT NULL,
  PRIMARY KEY (`id`)
);