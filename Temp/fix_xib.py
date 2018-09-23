
import os
import re
import sys


def process_xib_file(path):
    with open(path, 'r') as f:
        old_content = f.readlines()

    new_content = []

    for line in old_content:
        if not re.match(r'^\s*<color.+$\n', line):
            new_content.append(line)

    if len(old_content) != len(new_content):
        with open(path, 'w') as f:
            f.writelines(new_content)


def process_directory(path):
    for root, _, files in os.walk(path):
        for filename in files:
            if not filename.endswith('.xib'):
                continue

            process_xib_file(root + os.sep + filename)


def main():
    if 1 == len(sys.argv):
        print('Usage: %s directory ...' % sys.argv[0])
        return

    for path in sys.argv[1:]:
        process_directory(path)


if '__main__' == __name__:
    main()
