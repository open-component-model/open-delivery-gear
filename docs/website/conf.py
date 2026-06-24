# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'Open Delivery Gear'
copyright = '2026, Neo Nephos'
author = 'ODG Team'

# -- General configuration ---------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#general-configuration

extensions = ['myst_parser', 'sphinx_design', 'sphinxcontrib.mermaid']

# MyST-Parser configuration
source_suffix = {
    '.rst': 'restructuredtext',
    '.md': 'markdown',
}

# Enable MyST extensions for sphinx-design
myst_enable_extensions = [
    "colon_fence",  # ::: syntax for directives
]

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output

html_theme = 'furo'
html_static_path = ['_static']
html_favicon = '_static/odg.svg'
html_logo = '_static/odg.svg'
