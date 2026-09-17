# Makefile
dashboard:
  cd charts/aduke-monitoring/dashboard/jsonnet && \
  jb install && \
  jsonnet -J vendor golden-signals.jsonnet > ../golden-signals.json