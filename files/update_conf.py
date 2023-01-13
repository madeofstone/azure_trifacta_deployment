import json
import sys
import re
from os.path import exists
from shutil import copyfile
from typing import List


#conf_dir = "/Users/ppayandeh/code/python/triconf/"
template_file = "trifacta-conf.json.template"
conf_dir = "/opt/trifacta/conf/"

class DynamicAccessNestedDict:
    """Dynamically get/set nested dictionary keys of 'data' dict"""

    def __init__(self, data: dict):
        self.data = data

    def getval(self, keys: List):
        data = self.data
        for k in keys:
            data = data[k]
        return data

    def setval(self, keys: List, val: str) -> None:
        data = self.data
        val = val.strip()
        lastkey = re.sub(r'_DOT_', ".", keys[-1].strip())
        # print(lastkey)
        # print("val: |" + val + "|")

        # when assigning drill down to *second* last key
        for k in keys[:-1]:
            k = re.sub(r'_DOT_', ".", k)
            data = data[k]

        value = None
        if val.strip().startswith("\""):
            value = val.replace("\"", "").strip()
        else:
            if val.lower() == "true":
                value = True
            elif val.lower() == "false":
                value = False
            elif val.isdigit():
                value = int(val)
            elif val.isdecimal():
                value = float(val)
            elif val.startswith("["):
                value = json.loads(val)

        data[lastkey] = value





def ensure_triconf_backup_file_exists():
    template_file_full_path = conf_dir + template_file
    if exists(template_file_full_path):
        print("template file exists")
    else:
        print("template file doesn't exist")
        src_file = conf_dir + "trifacta-conf.json"
        copyfile(src=src_file, dst=template_file_full_path)


def read_conf_file():
    conf_lines = []
    if len(sys.argv) > 1:
        config_file = open( sys.argv[1] + "/config.txt")
    else:
        config_file = open("./config.txt")

    print(config_file)

    for line in config_file.readlines():
        line = line.strip()
        if not line: # ignore empty lines
            pass
        else:
            # ignore comment lines starting with #
            if line.strip().startswith("#"):
                pass
            else:
                conf_lines.append(line)
    return conf_lines


ensure_triconf_backup_file_exists()
config_list = read_conf_file()

tri_conf_file = open(conf_dir + template_file, mode="r")
tri_conf_dict = DynamicAccessNestedDict(json.load(tri_conf_file))

for config in config_list:
    key, val_str = config.split("=",1)
    key_list = key.split(".")
    tri_conf_dict.setval(key_list, val_str)

output = open(conf_dir + "trifacta-conf.json", mode="w")
output.write(json.dumps(tri_conf_dict.data, indent=2))
output.close()