#!/usr/bin/env python3
"""
This script updates README.md files and Jekyll pages with information about recent changes,
making it compatible with GitHub Pages Jekyll sites.
"""

import os
import re
import datetime
import glob
from github import Github
from pathlib import Path

# Number of recent files to show per directory
NUM_FILES = 10

# Files and directories to exclude (can be extended)
EXCLUDE_PATTERNS = [
    r'^\.git.*',
    r'^\.github.*',
    r'^LICENSE$',
    r'^\.gitignore$',
    r'^_site/.*',    # Jekyll build directory
    r'^\.sass-cache/.*',  # Jekyll cache directory
    r'^\.jekyll-cache/.*',  # Jekyll cache directory
    r'^vendor/.*',   # Jekyll vendor directory
]

# Jekyll-specific directories that should be included in file updates
JEKYLL_DIRS = [
    '_posts',
    '_pages',
    '_layouts',
    '_includes',
    'assets',
    'img',
    'video',
]

# Define the section markers - compatible with Jekyll
START_MARKER = "<!-- RECENT_CHANGES_START -->"
END_MARKER = "<!-- RECENT_CHANGES_END -->"

def should_exclude(path):
    """Check if the file path should be excluded."""
    for pattern in EXCLUDE_PATTERNS:
        if re.match(pattern, path):
            return True
    return False

def find_readme_and_index_files():
    """Find all README.md and index.md files (for Jekyll) in the repository."""
    markdown_files = []
    
    # Find all README.md files
    for root, dirs, files in os.walk('.'):
        if any(exclude in root for exclude in ['.git', '_site', '.jekyll-cache', '.sass-cache']):
            continue
            
        for file in files:
            if file.lower() == 'readme.md' or file.lower() == 'index.md':
                file_path = os.path.join(root, file)
                # Convert to relative path and normalize
                file_path = os.path.normpath(file_path)
                if file_path.startswith('./'):
                    file_path = file_path[2:]
                markdown_files.append(file_path)
    
    return markdown_files

def is_jekyll_file(file_path):
    """Check if a file is a Jekyll page or post."""
    # Check if file is in a Jekyll directory
    for jekyll_dir in JEKYLL_DIRS:
        if file_path.startswith(f"{jekyll_dir}/"):
            return True
    
    # Check if file has Jekyll front matter
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read(500)  # Read first 500 chars
            return content.strip().startswith('---')
    except:
        return False
    
    return False

def get_directory_changes(directory, all_file_updates):
    """Get files in the specified directory that have been recently updated."""
    directory_path = os.path.dirname(directory)
    if directory_path == '':  # Root directory
        directory_prefix = ''
    else:
        directory_prefix = directory_path + '/'
    
    # Filter files for this directory
    dir_files = {}
    for file_path, info in all_file_updates.items():
        # Check if file is in this directory or subdirectory
        if file_path.startswith(directory_prefix):
            # Skip the file itself from showing up in its own changes list
            if file_path == directory:
                continue
            dir_files[file_path] = info
    
    # Sort files by date (newest first) and take top N
    sorted_files = sorted(
        dir_files.items(),
        key=lambda x: x[1]['date'],
        reverse=True
    )[:NUM_FILES]
    
    return sorted_files

def get_repo_changes():
    """Get all recently updated files from the repository."""
    # Initialize GitHub client using the token
    token = os.environ.get('GITHUB_TOKEN')
    g = Github(token)
    
    # Get the repository name from environment
    repo_name = os.environ.get('GITHUB_REPOSITORY')
    repo = g.get_repo(repo_name)
    
    # Get the default branch commits
    default_branch = repo.default_branch
    commits = repo.get_commits(sha=default_branch)
    
    # Track files and their last modification date
    file_updates = {}
    
    # Process up to the last 100 commits to find recent changes
    for commit in commits[:100]:
        commit_date = commit.commit.author.date
        
        # For each file modified in this commit
        for file in commit.files:
            file_path = file.filename
            
            # Skip excluded files
            if should_exclude(file_path):
                continue
                
            # Only track the most recent update for each file
            if file_path not in file_updates or commit_date > file_updates[file_path]['date']:
                file_updates[file_path] = {
                    'date': commit_date,
                    'commit_message': commit.commit.message.split('\n')[0],  # Get first line of commit message
                    'commit_url': commit.html_url,
                    'author': commit.commit.author.name
                }
    
    return file_updates

def update_file(file_path, all_file_updates):
    """Update a specific markdown file with changes relevant to its directory."""
    # Check if this is a Jekyll file
    is_jekyll = is_jekyll_file(file_path)
    
    # Read the current file
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            content = file.read()
    except FileNotFoundError:
        # Create a basic file if not found
        directory_name = os.path.dirname(file_path) or "Root"
        if os.path.basename(file_path).lower() == 'index.md':
            # For Jekyll index files, include front matter
            content = "---\n"
            content += "layout: default\n"
            content += f"title: {directory_name.capitalize()} Directory\n"
            content += "---\n\n"
            content += f"# {directory_name.capitalize()} Directory\n\n"
        else:
            content = f"# {directory_name.capitalize()} Directory\n\n"
    
    # Get directory-specific changes
    recent_files = get_directory_changes(file_path, all_file_updates)
    
    # Format the recent changes section
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    recent_changes_content = f"{START_MARKER}\n"
    
    # For Jekyll files, use proper heading levels
    if is_jekyll:
        recent_changes_content += f"## Recently Updated Files\n\n"
    else:
        recent_changes_content += f"## Recently Updated Files\n\n"
    
    recent_changes_content += f"*Last updated: {current_time}*\n\n"
    
    if recent_files:
        recent_changes_content += "| File | Last Updated | Author | Commit Message |\n"
        recent_changes_content += "| ---- | ------------ | ------ | -------------- |\n"
        
        for file_path, info in recent_files:
            date_str = info['date'].strftime("%Y-%m-%d")
            commit_msg = info['commit_message']
            if len(commit_msg) > 60:  # Truncate long commit messages
                commit_msg = commit_msg[:57] + "..."
            
            # Create relative path from this file to the changed file
            current_dir = os.path.dirname(file_path)
            if current_dir:
                rel_path = os.path.relpath(file_path, current_dir)
            else:
                rel_path = file_path
            
            # Create link to the file (handle spaces in path)
            file_link = rel_path.replace(' ', '%20')
            
            # For Jekyll sites, create proper site URLs
            if is_jekyll:
                # Create Jekyll-compatible URLs (use site.baseurl if needed)
                file_name = os.path.basename(file_path)
                file_ext = os.path.splitext(file_name)[1]
                
                # Handle different file types for Jekyll
                if file_path.startswith('_posts/'):
                    # Extract date and slug from post filename
                    post_match = re.match(r'_posts/(\d{4}-\d{2}-\d{2})-(.*?)\.md', file_path)
                    if post_match:
                        date_part, slug = post_match.groups()
                        file_link = f"/blog/{slug}"
                        file_name = f"{date_part}: {slug.replace('-', ' ')}"
                    else:
                        file_link = f"/{file_path.replace('.md', '/')}"
                elif file_ext in ['.md', '.markdown'] and not file_path.endswith('README.md'):
                    # Convert .md files to their Jekyll URL equivalent
                    file_link = f"/{file_path.replace('.md', '/').replace('.markdown', '/')}"
                else:
                    # For other files, use direct path
                    file_link = f"/{file_path}"
                
                # Handle the special case of README.md files when in Jekyll
                if file_name.lower() == 'readme.md':
                    file_name = os.path.basename(os.path.dirname(file_path) or "Main")
            else:
                # For regular README files, just show the basename
                file_name = os.path.basename(file_path)
            
            recent_changes_content += f"| [{file_name}]({file_link}) | {date_str} | {info['author']} | [{commit_msg}]({info['commit_url']}) |\n"
    else:
        recent_changes_content += "*No recent changes found in this directory*\n"
    
    recent_changes_content += f"\n{END_MARKER}"
    
    # Check if the section markers already exist in the file
    if START_MARKER in content and END_MARKER in content:
        # Replace the existing section
        pattern = f"{re.escape(START_MARKER)}.*?{re.escape(END_MARKER)}"
        new_content = re.sub(pattern, recent_changes_content, content, flags=re.DOTALL)
    else:
        # Append the section to the end of the file
        new_content = content + "\n\n" + recent_changes_content
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(file_path) or '.', exist_ok=True)
    
    # Write the updated content back to the file
    with open(file_path, 'w', encoding='utf-8') as file:
        file.write(new_content)
    
    print(f"Updated {file_path} with {len(recent_files)} recent changes.")

def create_jekyll_indexes():
    """Create index.md files in directories that don't have one but should."""
    # Directories that typically need index files in Jekyll sites
    for jekyll_dir in JEKYLL_DIRS:
        if os.path.isdir(jekyll_dir) and not os.path.exists(os.path.join(jekyll_dir, 'index.md')):
            index_path = os.path.join(jekyll_dir, 'index.md')
            with open(index_path, 'w', encoding='utf-8') as file:
                file.write(f"---\n")
                file.write(f"layout: default\n")
                file.write(f"title: {jekyll_dir.capitalize()} Directory\n")
                file.write(f"---\n\n")
                file.write(f"# {jekyll_dir.capitalize()} Directory\n\n")
                file.write(f"This directory contains {jekyll_dir.lower()} files.\n\n")
                file.write(f"{START_MARKER}\n")  # Add marker for future updates
                file.write(f"## Recently Updated Files\n\n")
                file.write(f"*Updates will appear here after the next run*\n\n")
                file.write(f"{END_MARKER}")
            print(f"Created new Jekyll index file: {index_path}")

def update_all_files():
    """Find and update all README.md and index.md files in the repository."""
    # Create Jekyll indexes where needed
    create_jekyll_indexes()
    
    # Find all README.md and index.md files
    markdown_files = find_readme_and_index_files()
    print(f"Found {len(markdown_files)} README.md and index.md files")
    
    # Get all file changes once (to avoid multiple API calls)
    all_file_updates = get_repo_changes()
    print(f"Found {len(all_file_updates)} updated files in the repository")
    
    # Update each file with relevant changes
    for file_path in markdown_files:
        update_file(file_path, all_file_updates)

if __name__ == "__main__":
    # Ensure the .github/scripts directory exists
    os.makedirs('.github/scripts', exist_ok=True)
    
    # Update all markdown files
    update_all_files()
