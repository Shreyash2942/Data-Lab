# Python Layer

All Python samples live under `~/python` inside the container (mirrors `repo_root/python` on the host). The default interpreter is Python 3.10, already bundled with the dependencies used in the demos.

## Layout

| Path | Purpose |
| --- | --- |
| `python/example.py` | Simple script that prints version info and environment details. Use it as a template for small jobs. |

Add more modules/scripts here and they immediately become available inside the container at the same path.

## Running the example

From inside the container:

```bash
cd ~/python
python example.py
```

You can also invoke it from anywhere via the helper menu:

```bash
bash ~/app/services_demo.sh --run-python-example   # or choose option 1 in the menu
```

Need additional packages? Install them in the container (or bake them into the Docker image) and commit a `requirements.txt` alongside your scripts.

## Notes

- Project code and runtime state share the same home directory regardless of whether you run as `root` or `datalab`.
- Logs or generated artifacts should land in `~/runtime/python` (create it as needed) so they persist on the host and stay out of version control.

## Resources

- Official docs: https://docs.python.org/3/
