run: echo "experiment 2 running at $(date -u +%Y-%m-%dT%H:%M:%SZ)" && python3 -c "import time; time.sleep(2); print(\"exp 2 compute done\")" && echo "exp 2 complete"
