SELECT DISTINCT
cl.login as 'user',
dom.`name` as 'domain',
GROUP_CONCAT(DISTINCT db.`name`) AS 'db_list',
GROUP_CONCAT(DISTINCT ht.www_root) AS 'www_list',
GROUP_CONCAT(fwds.redirect,'[',fwds.http_code,']') AS fwd_list
FROM
clients AS cl
INNER JOIN domains AS dom ON cl.id = dom.cl_id
LEFT JOIN data_bases AS db ON dom.id = db.dom_id
LEFT JOIN hosting AS ht ON dom.id = ht.dom_id
LEFT JOIN forwarding AS fwds ON dom.id = fwds.dom_id
WHERE
cl.id NOT LIKE 1
GROUP BY
cl.login,
dom.`name`
ORDER BY
cl.login ASC
