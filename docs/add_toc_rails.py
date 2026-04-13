#!/usr/bin/env python3
"""
Add TOC rail to all HarbourBuilder documentation HTML files.
- Adds id attributes to h2/h3 headings that lack them
- Generates the right sidebar TOC rail for each page
"""

import os
import re
import glob
import unicodedata

DOCS_DIR = '/Users/usuario/tmp/HarbourBuilder/docs'

def slugify(text):
    """Convert heading text to a valid HTML id."""
    # Remove HTML tags
    text = re.sub(r'<[^>]+>', '', text)
    # Remove HTML entities
    text = re.sub(r'&[^;]+;', ' ', text)
    # Lowercase and replace spaces with hyphens
    text = text.lower().strip()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[\s]+', '-', text)
    text = re.sub(r'-+', '-', text)
    return text.strip('-')

def add_ids_and_extract_headings(content):
    """Add IDs to headings that lack them and extract all h2/h3."""
    headings = []
    
    def process_heading(match):
        level = match.group(1)
        existing_id = match.group(2)
        heading_text = match.group(3)
        
        if existing_id:
            heading_id = existing_id
        else:
            heading_id = slugify(heading_text)
        
        headings.append({
            'level': int(level),
            'id': heading_id,
            'text': re.sub(r'<[^>]+>', '', heading_text).strip()
        })
        
        if existing_id:
            return match.group(0)  # Return unchanged
        else:
            return f'<h{level} id="{heading_id}">{heading_text}</h{level}>'
    
    # Match h2 and h3 tags (with or without id)
    pattern = r'<h([23])(?:\s+id="([^"]*)")?[^>]*>(.*?)</h\1>'
    content = re.sub(pattern, process_heading, content, flags=re.DOTALL)
    
    return content, headings

def generate_toc_rail(headings, lang='en'):
    """Generate TOC rail HTML from list of headings."""
    if not headings:
        return ''
    
    titles = {
        'en': 'On This Page',
        'es': 'En Esta Página',
        'pt': 'Nesta Página'
    }
    
    toc_title = titles.get(lang, 'On This Page')
    
    toc = ['<!-- Table of Contents Rail -->', '<div class="toc-rail">', f'  <h4>{toc_title}</h4>']
    
    for i, h in enumerate(headings):
        indent = 'toc-h2' if h['level'] == 2 else 'toc-h3'
        active = ' active' if i == 0 else ''
        # Escape any special chars in text
        text = h['text'].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        toc.append(f'  <a href="#{h["id"]}" class="{indent}{active}">{text}</a>')
    
    toc.append('</div>')
    return '\n'.join(toc)

def detect_language(filepath):
    """Detect language from file path."""
    if '/es/' in filepath:
        return 'es'
    elif '/pt/' in filepath:
        return 'pt'
    return 'en'

def add_toc_to_file(html_path):
    """Add TOC rail to a single HTML file."""
    with open(html_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Skip if already has TOC rail (and it's well-formed)
    if '<div class="toc-rail">' in content and '<h4>' in content:
        # Still need to add IDs to headings
        content, headings = add_ids_and_extract_headings(content)
        with open(html_path, 'w', encoding='utf-8') as f:
            f.write(content)
        return False, len(headings)
    
    # Add IDs and extract headings
    content, headings = add_ids_and_extract_headings(content)
    
    if not headings:
        return False, 0
    
    # Generate TOC rail
    lang = detect_language(html_path)
    toc_rail = generate_toc_rail(headings, lang)
    
    # Remove any old inline TOC scripts
    content = re.sub(
        r'\n<!-- Table of Contents Rail -->.*?<script src="\.\./\.\./assets/js/docs\.js"></script>',
        '\n<script src="../assets/js/docs.js"></script>',
        content,
        flags=re.DOTALL
    )
    
    content = re.sub(
        r'\n<script>\s*// Scroll spy.*?</script>',
        '',
        content,
        flags=re.DOTALL
    )
    
    # Insert TOC rail before </body>
    # Find the last </div> that closes .content
    # Pattern: look for </div> followed by script tag
    pattern = r'(\n</div>\s*\n)(<script src="\.\.\/assets\/js\/docs\.js"><\/script>)'
    
    if re.search(pattern, content):
        content = re.sub(
            pattern,
            f'\n\n{toc_rail}\n\n\\2',
            content
        )
    else:
        # Fallback: insert before script tag
        content = content.replace(
            '<script src="../assets/js/docs.js"></script>',
            f'\n{toc_rail}\n\n<script src="../assets/js/docs.js"></script>'
        )
    
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    return True, len(headings)

def main():
    """Process all HTML files in docs directory."""
    html_files = glob.glob(f'{DOCS_DIR}/**/*.html', recursive=True)
    
    print(f"Found {len(html_files)} HTML files")
    print("Processing...\n")
    
    updated = 0
    skipped = 0
    no_headings = 0
    
    for html_file in sorted(html_files):
        rel_path = os.path.relpath(html_file, DOCS_DIR)
        
        try:
            result, heading_count = add_toc_to_file(html_file)
            if result:
                print(f"  ✓ {rel_path} ({heading_count} headings)")
                updated += 1
            else:
                if heading_count > 0:
                    print(f"  - {rel_path} (TOC exists, added IDs)")
                    skipped += 1
                else:
                    print(f"  ⚠ {rel_path} (no headings)")
                    no_headings += 1
        except Exception as e:
            print(f"  ✗ {rel_path}: {e}")
    
    print(f"\n{'='*60}")
    print(f"Updated: {updated}")
    print(f"Skipped (already had TOC): {skipped}")
    print(f"No headings found: {no_headings}")
    print(f"Total: {len(html_files)}")

if __name__ == '__main__':
    main()
