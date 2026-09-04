import os
import re
import sys
import xml.sax.saxutils as saxutils

print("--> [DEBUG]: Versioned Release Script initialized...")


def escape(text):
    return saxutils.escape(text)


def build_script_xml(name, source_content, class_name="ModuleScript"):
    return f'''\t<Item class="{class_name}" referent="RBX{os.urandom(8).hex()}">
\t\t<Properties>
\t\t\t<BinaryString name="AttributesSerialize"></BinaryString>
\t\t\t<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>
\t\t\t<bool name="DefinesCapabilities">false</bool>
\t\t\t<string name="Name">{escape(name)}</string>
\t\t\t<ProtectedString name="Source">{escape(source_content)}</ProtectedString>
\t\t\t<int64 name="SourceAssetId">-1</int64>
\t\t\t<BinaryString name="Tags"></BinaryString>
\t\t</Properties>
\t</Item>'''


def build_folder_xml(name, children_xml):
    indented_children = "\n".join(
        f"\t{line}" for line in children_xml.splitlines()
    )

    return f'''\t<Item class="Folder" referent="RBX{os.urandom(8).hex()}">
\t\t<Properties>
\t\t\t<BinaryString name="AttributesSerialize"></BinaryString>
\t\t\t<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>
\t\t\t<bool name="DefinesCapabilities">false</bool>
\t\t\t<string name="Name">{escape(name)}</string>
\t\t\t<int64 name="SourceAssetId">-1</int64>
\t\t\t<BinaryString name="Tags"></BinaryString>
\t\t</Properties>
{indented_children}
\t</Item>'''


def get_script_info(filename):
    """
    Returns:
        (script_name, Roblox class)
    """

    if filename.endswith(".server.luau"):
        return filename[:-len(".server.luau")], "Script"

    if filename.endswith(".server.lua"):
        return filename[:-len(".server.lua")], "Script"

    if filename.endswith(".client.luau"):
        return filename[:-len(".client.luau")], "LocalScript"

    if filename.endswith(".client.lua"):
        return filename[:-len(".client.lua")], "LocalScript"

    if filename.endswith(".luau"):
        return filename[:-len(".luau")], "ModuleScript"

    if filename.endswith(".lua"):
        return filename[:-len(".lua")], "ModuleScript"

    return None


def scan_directory(path):
    items_xml = []

    try:
        entries = sorted(os.listdir(path))
    except Exception:
        return ""

    for entry in entries:
        full_path = os.path.join(path, entry)

        if os.path.isdir(full_path):
            init_file = None

            for init_candidate in ("init.luau", "init.lua"):
                candidate = os.path.join(full_path, init_candidate)

                if os.path.isfile(candidate):
                    init_file = candidate
                    break

            children_content = scan_directory(full_path)

            if init_file:
                with open(
                    init_file,
                    "r",
                    encoding="utf-8",
                    errors="ignore"
                ) as f:
                    source = f.read()

                script_xml = build_script_xml(
                    entry,
                    source,
                    "ModuleScript"
                )

                if children_content:
                    indented_children = "\n".join(
                        f"\t{line}"
                        for line in children_content.splitlines()
                    )

                    lines = script_xml.splitlines()
                    lines.insert(-1, indented_children)
                    script_xml = "\n".join(lines)

                items_xml.append(script_xml)

            else:
                items_xml.append(
                    build_folder_xml(entry, children_content)
                )

        elif os.path.isfile(full_path):
            if entry in ("init.luau", "init.lua", "README.md"):
                continue

            script_info = get_script_info(entry)

            if script_info is None:
                continue

            name, class_name = script_info

            with open(
                full_path,
                "r",
                encoding="utf-8",
                errors="ignore"
            ) as f:
                source = f.read()

            items_xml.append(
                build_script_xml(
                    name,
                    source,
                    class_name
                )
            )

    return "\n".join(items_xml)


def calculate_next_version():
    """Scans the directory to find the highest existing version and increments it."""

    current_files = os.listdir(".")

    highest_major = 0
    highest_minor = 0
    highest_patch = 0
    found_any_version = False

    version_pattern = re.compile(
        r"Merveille\s+(\d+)\.(\d+)\.(\d+)\.rbxmx"
    )

    for filename in current_files:
        match = version_pattern.match(filename)

        if match:
            found_any_version = True
            major, minor, patch = map(int, match.groups())

            if (
                major > highest_major
                or (
                    major == highest_major
                    and minor > highest_minor
                )
                or (
                    major == highest_major
                    and minor == highest_minor
                    and patch > highest_patch
                )
            ):
                highest_major = major
                highest_minor = minor
                highest_patch = patch

    if not found_any_version:
        return "0.1.0"

    return f"{highest_major}.{highest_minor + 1}.0"


def main():
    target_dir = "MerveilleData"

    if (
        not os.path.exists(target_dir)
        and os.path.exists("MervielleData")
    ):
        target_dir = "MervielleData"

    if not os.path.exists(target_dir):
        print(
            f"--> [error]: Target folder '{target_dir}' is missing."
        )
        return

    next_version = calculate_next_version()
    output_filename = f"Merveille {next_version}.rbxmx"

    root_source = (
        f"-- [Merveille Core Runtime v{next_version}]\n"
    )

    for root_init in (
        f"{target_dir}/init.luau",
        f"{target_dir}/init.lua"
    ):
        if os.path.isfile(root_init):
            with open(root_init, "r", encoding="utf-8") as f:
                root_source += f.read()
            break

    children_xml = scan_directory(target_dir)

    core_module = build_script_xml(
        "MerveilleData",
        root_source,
        "ModuleScript"
    )

    if children_xml:
        indented_children = "\n".join(
            f"\t{line}"
            for line in children_xml.splitlines()
        )

        lines = core_module.splitlines()
        lines.insert(-1, indented_children)
        core_module = "\n".join(lines)

    xml_output = f'''<roblox xmlns:xmime="http://w3.org" xmlns:xs="http://w3.org" xsi:noNamespaceSchemaLocation="http://roblox.com" version="4" xmlns:xsi="http://w3.org-instance">
\t<Meta name="ExplicitAutoJoints">true</Meta>
\t<External>null</External>
\t<External>nil</External>
{core_module}
</roblox>'''

    try:
        with open(output_filename, "w", encoding="utf-8") as f:
            f.write(xml_output)

        print(
            f"--> [SUCCESS]: Compiled and tagged release: "
            f"'{output_filename}'"
        )

    except Exception as e:
        print(
            f"--> [error]: Failed writing release build: {e}"
        )


if __name__ == "__main__":
    main()