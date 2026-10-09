run: echo "experiment 1 running at $(date -u +%Y-%m-%dT%H:%M:%SZ)" && python3 -c "import time; time.sleep(2); print(\"exp 1 compute done\")" && echo "exp 1 complete"
