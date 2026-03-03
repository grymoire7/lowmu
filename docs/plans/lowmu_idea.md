# lowmu (Low Friction Publishing Tool)

This is a CLI tool that lowers the friction of publishing blog posts and
related content to social web.

## The problem we're trying to solve

I want to publish more content to more places, but there is friction in the
process. `lowmu` (low mu) is meant to be a tool that lowers the friction of
publishing content to multiple platforms. The name "lowmu" is a play on the
term "low friction" and the Greek letter "mu" (μ), which is often used to
represent the coefficient of friction in physics.

The idea is to take an original markdown file (long/post or short/note content)
and a hero image, and then use the metadata in the markdown file to determine
which platforms to publish to and how to format the content for each platform. The
tool would then generate the appropriate output files for each target platform based
on the original content and the platform's specific requirements. This would
allow the user to write their content once and publish it to multiple platforms
without having to manually format it for each one, thus reducing the friction
of publishing to multiple platforms.

For my own blog (a hugo site), the produced content (markdown and image) would
be copied to the appropriate location in my hugo site's content directory, and
when the files are committed and pushed to Github, the hugo site would be
automatically built and deployed to my hosting provider via github actions
(already in place).

For platforms like Substack and Mastodon, the tool would use the platform API
to publish the content directly from the command line. LinkedIn content will
likely get generated but will require manual copy-pasting to publish, since
LinkedIn's API is not as straightforward for content publishing -- at least for
now.

Generation of content and publishing would be separate steps, so the user can
review and edit the generated content before it gets published. The tool would
also update a status file to keep track of which posts have been published to
which platforms, so the user can easily see the publishing status (`lowmu status`).

The tool would also update a status file to keep track of which posts have been
published to which platforms.

## Some initial thoughts on the design and functionality of lowmu

```bash
$ lowmu --help
Usage: lowmu [options] <command>

Description:
  lowmu is a CLI tool that lowers the friction of publishing blog posts and
  related content to social web.

Commands:
  lowmu [--]help                    Display this help message
  lowmu help <command>              Display help for a specific command
  lowmu configure [options]         Create or update configuration file
  lowmu status [options]            Report status of content and publishing targets
                                    for one or all content slugs
  lowmu publish [options] <slug>    Publish <slug> content to configured targets
  lowmu new [options] <content_md_path> <hero_image_path>
                                    Create a new set of content files

Examples:
  # Write a fresh config.yml file to ~/.config/lowmu/config.yml
  lowmu configure
  
  lowmu publish my-new-post
  lowmu new ./content/my-new-post.md ./images/my-new-post-hero.jpg

```

Example configuration file:

```yaml
# Example lowmu configuration file
# This file is typically located at ~/.config/lowmu/config.yml
# Configuration for lowmu CLI tool
# Path to the directory where output content is stored
# $content_dir/
# |- <slug>/
#    |- original_content.md     # the original markdown file created by the user
#    |- <target_name>.[md|html] # the format depends on the target's requirements
#    |- hero_image.jpg          # the hero image for the post, used by targets that support it
#    |- status.yml              # contains metadata about the publishing status for each target
content_dir: ~/projects/lowmu/content

# List of publishing targets
targets:
  # Example target for publishing to a blog
  - name: tracyatteberry
    type: hugo
    # The base URL of the blog
    base_url: https://tracyatteberry.com
    # The path to the directory where the blog's content files are stored
    base_path: ~/projects/tracyatteberry/content
  # Example target for publishing to Substack
  - name: substack
    type: substack
    # Authentication credentials for the Substack API
    auth:
      type: api_key
      api_key: your_substack_api_key_here
```
Original markdown content has metadata in the front matter that lowmu can use
to determine which targets to publish to and how to format the content for each
target. For example:

```markdown
---
title: My New Post
date: 2024-01-01 # publish date
type: post       # [post, note]
tags: [tag1, tag2]
publish_to:
  - tracyatteberry
  - substack
---
This is the content of my new post. It will be published to both my Hugo blog and
my Substack newsletter with the appropriate formatting for each platform.
```


