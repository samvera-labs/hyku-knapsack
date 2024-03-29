# frozen_string_literal: true

# This is a copy of the Hyrax work generate adapted for use in the Knapsack.
# example:
#   `bundle exec rails generate hyku_knapsack:work_resource WorkType`
#
# This will ensure the generated files get created in the knapsack and not the submodule
require 'rails/generators'
require 'rails/generators/model_helpers'

# rubocop:disable Metrics/ClassLength
class HykuKnapsack::WorkResourceGenerator < Rails::Generators::NamedBase
  # ActiveSupport can interpret models as plural which causes
  # counter-intuitive route paths. Pull in ModelHelpers from
  # Rails which warns users about pluralization when generating
  # new models or scaffolds.
  include Rails::Generators::ModelHelpers

  TEMPLATE_PATH = Hyrax::Engine.root.join('lib', 'generators', 'hyrax', 'work_resource', 'templates')
  source_root File.expand_path(TEMPLATE_PATH, __FILE__)

  argument :attributes, type: :array, default: [], banner: 'field:type field:type'

  def self.exit_on_failure?
    true
  end

  def validate_name
    return unless name.strip.casecmp("work").zero?
    raise Thor::MalformattedArgumentError,
          set_color("Error: A work resource with the name '#{name}' would cause name-space clashes. "\
                    "Please use a different name.", :red)
  end

  def banner
    if revoking?
      say_status("info", "DESTROYING VALKYRIE WORK MODEL: #{class_name}", :blue)
    else
      say_status("info", "GENERATING VALKYRIE WORK MODEL: #{class_name}", :blue)
    end
  end

  def create_controller
    template('controller.rb.erb', File.join('../app/controllers/hyrax', class_path, "#{plural_file_name}_controller.rb"))
  end

  def create_metadata_config
    template('metadata.yaml', File.join('../config/metadata/', "#{file_name}.yaml"))
    return if attributes.blank?
    gsub_file File.join('config/metadata/', "#{file_name}.yaml"),
              'attributes: {}',
              { 'attributes' => attributes.collect { |arg| [arg.name, { 'type' => arg.type.to_s }] }.to_h }.to_yaml
  end

  def create_model
    template('work.rb.erb', File.join('../app/models/', class_path, "#{file_name}.rb"))
  end

  def create_model_spec
    return unless rspec_installed?
    filepath = File.join('../spec/models/', class_path, "#{file_name}_spec.rb")
    template('work_spec.rb.erb', filepath)
    return if attributes.blank?
    inject_into_file filepath, after: /it_behaves_like 'a Hyrax::Work'\n/ do
      "\n  context 'includes schema defined metadata' do\n"\
      "#{attributes.collect { |arg| "    it { is_expected.to respond_to(:#{arg.name}) }\n" }.join}" \
      "  end\n"
    end
  end

  def create_form
    template('form.rb.erb', File.join('../app/forms/', class_path, "#{file_name}_form.rb"))
  end

  # Inserts after the last registered work, or at the top of the config block
  def register_work
    config = '../config/initializers/hyrax.rb'
    lastmatch = nil
    in_root do
      File.open(config).each_line do |line|
        lastmatch = line if line.match?(/config.register_curation_concern :(?!#{file_name})/)
      end
      content = "  # Injected via `rails g hyrax:work_resource #{class_name}`\n" \
                "  config.register_curation_concern #{registration_path_symbol}\n"
      anchor = lastmatch || "Hyrax.config do |config|\n"
      inject_into_file config, after: anchor do
        content
      end
    end
  end

  def create_indexer
    template('indexer.rb.erb', File.join('../app/indexers/', class_path, "#{file_name}_indexer.rb"))
  end

  def create_indexer_spec
    return unless rspec_installed?
    filepath = File.join('../spec/indexers/', class_path, "#{file_name}_indexer_spec.rb")
    template('indexer_spec.rb.erb', filepath)
  end

  def create_views
    create_file File.join('../app/views/hyrax', class_path, "#{plural_file_name}/_#{file_name}.html.erb") do
      "<%# This is a search result view %>\n" \
      "<%= render 'catalog/document', document: #{file_name}, document_counter: #{file_name}_counter  %>\n"
    end
  end

  def create_view_spec
    return unless rspec_installed?
    template('work.html.erb_spec.rb.erb',
             File.join('../spec/views/', class_path, "#{plural_file_name}/_#{file_name}.html.erb_spec.rb"))
  end

  def insert_hyku_works_controller_behavior
    controller = File.join('../app/controllers/hyrax', class_path, "#{plural_file_name}_controller.rb")
    insert_into_file controller, after: "include Hyrax::WorksControllerBehavior\n" do
      "    include Hyku::WorksControllerBehavior\n"
    end
  end

  def insert_hyku_extra_includes_into_model
    model = File.join('../app/models/', class_path, "#{file_name}.rb")
    insert_into_file model, before: "end" do
      <<-RUBY.gsub(/^ {8}/, '  ')
        include Hyrax::Schema(:with_pdf_viewer)
        include Hyrax::Schema(:with_video_embed)
        include Hyrax::ArResource
        include Hyrax::NestedWorks

        include IiifPrint.model_configuration(
          pdf_split_child_model: GenericWorkResource,
          pdf_splitter_service: IiifPrint::TenantConfig::PdfSplitter
        )

        prepend OrderAlready.for(:creator)
      RUBY
    end
  end

  private

  def rspec_installed?
    defined?(RSpec) && defined?(RSpec::Rails)
  end

  def registration_path_symbol
    return ":#{file_name}" if class_path.blank?
    # creates a symbol with a path like "abc/scholarly_paper" where abc
    # is the namespace and scholarly_paper is the resource name
    ":\"#{File.join(class_path, file_name)}\""
  end

  def revoking?
    behavior == :revoke
  end
end
# rubocop:enable Metrics/ClassLength
