run: echo "experiment 5 running at $(date -u +%Y-%m-%dT%H:%M:%SZ)" && python3 -c "import time; time.sleep(2); print(\"exp 5 compute done\")" && echo "exp 5 complete"
