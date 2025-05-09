-- populate-rights relies on this table for now so that it can update the status
-- in ingest to 'done' from 'rights' -- should rethink this in the future if
-- ingest gets more event-oriented

CREATE TABLE IF NOT EXISTS `feed_queue` (
  `pkg_type` varchar(32) DEFAULT NULL,
  `namespace` varchar(8) NOT NULL DEFAULT '',
  `id` varchar(32) NOT NULL DEFAULT '',
  `status` varchar(20) NOT NULL DEFAULT 'ready',
  `reset_status` varchar(20) DEFAULT NULL,
  `update_stamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `date_added` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `node` varchar(255) DEFAULT NULL,
  `failure_count` int(11) NOT NULL DEFAULT '0',
  `priority` int(11) DEFAULT NULL,
  PRIMARY KEY (`namespace`,`id`),
  KEY `queue_pkg_type_status_idx` (`pkg_type`,`status`),
  KEY `queue_node_idx` (`node`),
  KEY `queue_priority_idx` (`priority`,`date_added`),
  KEY `queue_node_status_index` (`node`,`status`)
);

CREATE TABLE IF NOT EXISTS `feed_grin` (
  `namespace` varchar(10) NOT NULL DEFAULT '',
  `id` varchar(30) NOT NULL DEFAULT '',
  `checkin_date` datetime DEFAULT NULL,
  `state` varchar(30) DEFAULT NULL,
  `viewability` varchar(15) DEFAULT NULL,
  `conditions` varchar(30) DEFAULT NULL,
  `scannable` varchar(5) DEFAULT NULL,
  `opted_out` varchar(5) DEFAULT NULL,
  `tagging` varchar(5) DEFAULT NULL,
  `audit` varchar(30) DEFAULT NULL,
  `material_error` varchar(4) DEFAULT NULL,
  `overall_error` varchar(4) DEFAULT NULL,
  `scan_date` datetime DEFAULT NULL,
  `process_date` datetime DEFAULT NULL,
  `analyze_date` datetime DEFAULT NULL,
  `convert_date` datetime DEFAULT NULL,
  `allow_date` datetime DEFAULT NULL,
  `viewability_date` datetime DEFAULT NULL,
  `src_lib_bibkey` varchar(25) DEFAULT NULL,
  `rubbish` varchar(5) DEFAULT NULL,
  `dl_date` datetime DEFAULT NULL,
  `claimed` varchar(5) DEFAULT NULL,
  `ocr_gtd` varchar(4) DEFAULT NULL,
  `ocr_analysis` varchar(4) DEFAULT NULL,
  `digitization_method` varchar(32) DEFAULT NULL,
  `ocr_date` datetime DEFAULT NULL,
  PRIMARY KEY (`namespace`,`id`)
);
