"""WordPress.org metadata rules shared by generation and sealed-package checks."""
import re


def validate_minimum_wordpress(plugin_header, readme):
    """Require one matching stable major release (for example 6.6), not 6.6.4."""
    field = re.compile(r'^[ \t]*(?:\*[ \t]*)?Requires at least:[ \t]*(\S+)[ \t]*$', re.MULTILINE)
    values = []
    for name, text in [('plugin header', plugin_header), ('readme', readme)]:
        matches = field.findall(text)
        if len(matches) != 1 or not re.fullmatch(r'[1-9][0-9]*\.[0-9]+', matches[0]):
            raise ValueError(f'{name}: Requires at least must be one WordPress major release such as 6.6')
        values.append(matches[0])
    if values[0] != values[1]:
        raise ValueError('Requires at least differs between plugin header and readme')
    return values[0]
