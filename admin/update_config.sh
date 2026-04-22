#!/bin/bash

# Get the default branch
DEFAULT_BRANCH=$(git remote show origin | grep "HEAD branch" | cut -d' ' -f5)
if [ -z "$DEFAULT_BRANCH" ]; then
	DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
fi
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="18.0"

CURRENT_LOCAL_BRANCH=$(git branch --show-current)

# Get all branches
BRANCHES=$(git branch -a --format='%(refname:short)' | sed 's/origin\///' | sort -u | grep -v "HEAD")
readarray -t BRANCH_ARRAY <<<"$BRANCHES"

generate_config() {
	local branch=$1
	clean_branch_filename=$(echo "$branch" | tr '/' '-')
	local output="admin/config-$clean_branch_filename.yml"

	local ref="$branch"
	if ! git rev-parse --verify "$ref" >/dev/null 2>&1; then
		if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
			ref="origin/$branch"
		else
			echo "Warning: Could not find git ref for branch $branch. Skipping."
			return
		fi
	fi

	local is_local="true"

	echo "Generating $output for branch $branch (Ref: $ref)..."

	# Preliminary check for manifests (handles both __manifest__.py and __openerp__.py)
	local manifests=$(git ls-tree -r --name-only "$ref" | grep -E "__manifest__.py|__openerp__.py" | sort)

	cat <<EOF >"$output"
local_backend: $is_local
backend:
  name: github
  repo: yessser/web
  branch: "$branch"
  open_authoring: true
publish_mode: editorial_workflow

media_folder: "static/description"
public_folder: "/static/description"

collections:
EOF

	if [ -z "$manifests" ]; then
		# Add a dummy collection to prevent "collections must be array" error if no modules found
		cat <<EOF >>"$output"
  - name: "repo_docs"
    label: "Repository Docs"
    files:
      - name: "readme"
        label: "README.md"
        file: "README.md"
        fields:
          - { label: "Body", name: "body", widget: "markdown" }
EOF
	else
		FILES=("DESCRIPTION.md" "INSTALL.md" "CONTEXT.md" "CONFIGURE.md" "USAGE.md" "ROADMAP.md" "CREDITS.md" "CONTRIBUTORS.md")
		echo "$manifests" | while read -r manifest; do
			module_dir=$(dirname "$manifest")
			module_name=${module_dir#./}
			[ "$module_name" == "." ] && continue

			cat <<EOF >>"$output"
  - name: "$module_name"
    label: "$module_name"
    media_folder: "../static/description"
    public_folder: "../static/description"
    files:
EOF

			for filename in "${FILES[@]}"; do
				entry_name=$(echo "${filename%.*}" | tr '[:upper:]' '[:lower:]')
				cat <<EOF >>"$output"
      - name: "$entry_name"
        label: "$filename"
        file: "$module_name/readme/$filename"
        fields:
          - { label: "Title", name: "title", widget: "string", required: false }
          - { label: "Body", name: "body", widget: "markdown" }
EOF
			done
		done
	fi
}

for b in "${BRANCH_ARRAY[@]}"; do
	[ -n "$b" ] && generate_config "$b"
done

# Generate branches.json
echo "{" >admin/branches.json
echo "  \"default\": \"$DEFAULT_BRANCH\"," >>admin/branches.json
echo "  \"current\": \"$CURRENT_LOCAL_BRANCH\"," >>admin/branches.json
echo "  \"list\": [" >>admin/branches.json
for i in "${!BRANCH_ARRAY[@]}"; do
	b="${BRANCH_ARRAY[$i]}"
	if [ -n "$b" ]; then
		echo "    \"$b\"$([ $i -lt $((${#BRANCH_ARRAY[@]} - 1)) ] && echo ",")" >>admin/branches.json
	fi
done
echo "  ]" >>admin/branches.json
echo "}" >>admin/branches.json

clean_default_filename=$(echo "$DEFAULT_BRANCH" | tr '/' '-')
cp "admin/config-$clean_default_filename.yml" admin/config.yml 2>/dev/null

echo "Done."
