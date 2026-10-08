# Helper used by the labs to trigger bind() calls on demand.

try-bind: try-bind.c
	gcc -O2 -Wall -Werror $< -o $@

.PHONY: clean
clean:
	rm -f try-bind
