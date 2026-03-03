module Lowmu
  module Publishers
    class Hugo < Base
      def publish
        slug = File.basename(@slug_dir)
        base_path = File.expand_path(@target_config["base_path"])
        dest_dir = File.join(base_path, "posts", slug)

        FileUtils.mkdir_p(dest_dir)
        FileUtils.cp(generated_file_path(Generators::Hugo::OUTPUT_FILE), File.join(dest_dir, "index.md"))

        hero = Dir[File.join(@slug_dir, "hero_image.*")].first
        FileUtils.cp(hero, File.join(dest_dir, File.basename(hero))) if hero

        dest_dir
      end
    end
  end
end
