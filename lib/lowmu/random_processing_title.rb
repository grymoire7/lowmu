module Lowmu
  # RandomProcesingTitle provides a dynamic verb for spinners, making the user
  # experience more engaging during long-running tasks.
  class RandomProcessingTitle
    # To avoid the perception of repitition, we target a pool of 20 verbs per category.
    VERBS = {
      generic: [
        ["Processing", "Processed"],
        ["Generating", "Generated"],
        ["Creating", "Created"],
        ["Building", "Built"],
        ["Compiling", "Compiled"],
        ["Assembling", "Assembled"],
        ["Analyzing", "Analyzed"],
        ["Transforming", "Transformed"],
        ["Updating", "Updated"],
        ["Optimizing", "Optimized"],
        ["Calculating", "Calculated"],
        ["Rendering", "Rendered"],
        ["Indexing", "Indexed"],
        ["Migrating", "Migrated"],
        ["Deploying", "Deployed"],
        ["Testing", "Tested"],
        ["Validating", "Validated"],
        ["Refactoring", "Refactored"],
        ["Documenting", "Documented"],
        ["Debugging", "Debugged"]
      ],
      baking: [
        ["Baking", "Baked"],
        ["Cooking", "Cooked"],
        ["Roasting", "Roasted"],
        ["Grilling", "Grilled"],
        ["Frying", "Fried"],
        ["Simmering", "Simmered"],
        ["Boiling", "Boiled"],
        ["Steaming", "Steamed"],
        ["Broiling", "Broiled"],
        ["Sautéing", "Sautéed"],
        ["Blending", "Blended"],
        ["Whisking", "Whisked"],
        ["Marinating", "Marinated"],
        ["Glazing", "Glazed"],
        ["Caramelizing", "Caramelized"],
        ["Seasoning", "Seasoned"],
        ["Garnishing", "Garnished"],
        ["Plating", "Plated"],
        ["Serving", "Served"],
        ["Cooling", "Cooled"]
      ],
      crafting: [
        ["Crafting", "Crafted"],
        ["Sculpting", "Sculpted"],
        ["Carving", "Carved"],
        ["Weaving", "Woven"],
        ["Knitting", "Knitted"],
        ["Crocheting", "Crocheted"],
        ["Embroidery", "Embroidered"],
        ["Quilting", "Quilted"],
        ["Painting", "Painted"],
        ["Drawing", "Drawn"],
        ["Sketching", "Sketched"],
        ["Sanding", "Sanded"],
        ["Polishing", "Polished"],
        ["Staining", "Stained"],
        ["Varnishing", "Varnished"],
        ["Sewing", "Sewn"],
        ["Remixing", "Remixed"],
        ["Upcycling", "Upcycled"],
        ["Folding", "Folded"],
        ["Glassblowing", "Glassblown"],
        ["Molding", "Molded"],
        ["Modeling", "Modeled"]
      ]
    }

    def self.generate(category = :generic)
      VERBS[category].sample
    end
  end
end
