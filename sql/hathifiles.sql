-- Used by HathifilesDatabaseVerifier

CREATE TABLE IF NOT EXISTS `hf` (
  `htid` varchar(255) NOT NULL,
  `access` tinyint(1) DEFAULT NULL,
  `rights_code` varchar(255) DEFAULT NULL,
  `bib_num` bigint(20) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `source` varchar(255) DEFAULT NULL,
  `source_bib_num` text DEFAULT NULL,
  `oclc` varchar(255) DEFAULT NULL,
  `isbn` text DEFAULT NULL,
  `issn` text DEFAULT NULL,
  `lccn` varchar(255) DEFAULT NULL,
  `title` text DEFAULT NULL,
  `imprint` text DEFAULT NULL,
  `rights_reason` varchar(255) DEFAULT NULL,
  `rights_timestamp` datetime DEFAULT NULL,
  `us_gov_doc_flag` tinyint(1) DEFAULT NULL,
  `rights_date_used` int(11) DEFAULT NULL,
  `pub_place` varchar(255) DEFAULT NULL,
  `lang_code` varchar(255) DEFAULT NULL,
  `bib_fmt` varchar(255) DEFAULT NULL,
  `collection_code` varchar(255) DEFAULT NULL,
  `content_provider_code` varchar(255) DEFAULT NULL,
  `responsible_entity_code` varchar(255) DEFAULT NULL,
  `digitization_agent_code` varchar(255) DEFAULT NULL,
  `access_profile_code` varchar(255) DEFAULT NULL,
  `author` text DEFAULT NULL,
  KEY `hf_htid_index` (`htid`),
  KEY `hf_rights_code_index` (`rights_code`),
  KEY `hf_bib_num_index` (`bib_num`),
  KEY `hf_rights_reason_index` (`rights_reason`),
  KEY `hf_rights_timestamp_index` (`rights_timestamp`),
  KEY `hf_us_gov_doc_flag_index` (`us_gov_doc_flag`),
  KEY `hf_rights_date_used_index` (`rights_date_used`),
  KEY `hf_lang_code_index` (`lang_code`),
  KEY `hf_bib_fmt_index` (`bib_fmt`),
  KEY `hf_collection_code_index` (`collection_code`),
  KEY `hf_content_provider_code_index` (`content_provider_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;


CREATE TABLE IF NOT EXISTS `hf_log` (
  `hathifile` varchar(255) NOT NULL,
  `time` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;;
