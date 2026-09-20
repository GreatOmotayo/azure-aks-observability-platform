dashboard:
	cd charts/aduke-monitoring/dashboards/jsonnet && \
	jb install && \
	jsonnet -J vendor golden-signals.jsonnet > ../golden-signals.json
