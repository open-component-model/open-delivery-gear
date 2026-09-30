# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#project-information

project = 'Open Delivery Gear'
copyright = ''  # Empty - custom footer in template handles all text
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
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store', '.venv']

# -- Options for HTML output -------------------------------------------------
# https://www.sphinx-doc.org/en/master/usage/configuration.html#options-for-html-output

html_theme = 'furo'
html_static_path = ['_static']
html_favicon = '_static/odg.svg'
html_logo = '_static/odg.svg'
html_css_files = ['custom.css']
html_js_files = ['custom.js']

# Custom footer
html_theme_options = {
    "announcement": "🎉 <strong>New Release!</strong> ODG Service Provider (<strong>Beta</strong>) for Open Control Plane is now available. <a href='https://github.com/open-component-model/service-provider-odg' target='_blank'>Learn more</a>",
    "light_css_variables": {
        "color-brand-primary": "#2196F3",
        "color-brand-content": "#1976D2",
    },
    "dark_css_variables": {
        "color-brand-primary": "#90CAF9",
        "color-brand-content": "#64B5F6",
    },
    "footer_icons": [
        {
            "name": "GitHub",
            "url": "https://github.com/open-component-model/open-delivery-gear",
            "html": "",
            "class": "",
        },
    ],
}
