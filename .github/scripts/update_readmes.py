#!/usr/bin/env python3
"""
This script updates multiple README.md files across different directories with 
information about recent changes in their respective directories.
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
]

# Define the section markers
START_MARKER = "<!-- RECENT_CHANGES_START -->"
END_MARKER = "<!-- RECENT_CHANGES_END -->"

def should_exclude(path):
    """Check if the file path should be excluded."""
    for pattern in EXCLUDE_PATTERNS:
        if re.match(pattern, path):
            return True
    return False

def find_readme_files():
    """Find all README.md files in the repository."""
    readme_files = []
    for root, dirs, files in os.walk('.'):
        if '.git' in root:
            continue
        for file in files:
            if file.lower() == 'readme.md':
                readme_path = os.path.join(root, file)
                # Convert to relative path and normalize
                readme_path = os.path.normpath(readme_path)
                if readme_path.startswith('./'):
                    readme_path = readme_path[2:]
                readme_files.append(readme_path)
    
    return readme_files

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
            # Skip the README.md itself
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

def update_readme(readme_path, all_file_updates):
    """Update a specific README.md file with changes relevant to its directory."""
    # Read the current README
    try:
        with open(readme_path, 'r', encoding='utf-8') as file:
            content = file.read()
    except FileNotFoundError:
        # Create a basic README if not found
        directory_name = os.path.dirname(readme_path) or "Root"
        content = f"# {directory_name} Directory\n\n"
    
    # Get directory-specific changes
    recent_files = get_directory_changes(readme_path, all_file_updates)
    
    # Format the recent changes section
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    recent_changes_content = f"{START_MARKER}\n"
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
            
            # Create relative path from this README to the file
            readme_dir = os.path.dirname(readme_path)
            if readme_dir:
                rel_path = os.path.relpath(file_path, readme_dir)
            else:
                rel_path = file_path
            
            # Create link to the file (handle spaces in path)
            file_link = rel_path.replace(' ', '%20')
            
            # Display filename only (not full path) but link to the full path
            file_name = os.path.basename(file_path)
            recent_changes_content += f"| [{file_name}]({file_link}) | {date_str} | {info['author']} | [{commit_msg}]({info['commit_url']}) |\n"
    else:
        recent_changes_content += "*No recent changes found in this directory*\n"
    
    recent_changes_content += f"\n{END_MARKER}"
    
    # Check if the section markers already exist in the README
    if START_MARKER in content and END_MARKER in content:
        # Replace the existing section
        pattern = f"{re.escape(START_MARKER)}.*?{re.escape(END_MARKER)}"
        new_content = re.sub(pattern, recent_changes_content, content, flags=re.DOTALL)
    else:
        # Append the section to the end of the README
        new_content = content + "\n\n" + recent_changes_content
    
    # Write the updated content back to the README
    with open(readme_path, 'w', encoding='utf-8') as file:
        file.write(new_content)
    
    print(f"Updated {readme_path} with {len(recent_files)} recent changes.")

def update_all_readmes():
    """Find and update all README.md files in the repository."""
    # Find all README.md files
    readme_files = find_readme_files()
    print(f"Found {len(readme_files)} README.md files")
    
    # Get all file changes once (to avoid multiple API calls)
    all_file_updates = get_repo_changes()
    print(f"Found {len(all_file_updates)} updated files in the repository")
    
    # Update each README with relevant changes
    for readme_path in readme_files:
        update_readme(readme_path, all_file_updates)

if __name__ == "__main__":
    # Ensure the .github/scripts directory exists
    os.makedirs('.github/scripts', exist_ok=True)
    
    # Update all README files
    update_all_readmes()
