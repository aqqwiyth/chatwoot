class ContentAttributeValidator < ActiveModel::Validator
  ALLOWED_SELECT_ITEM_KEYS = [:title, :value].freeze
  ALLOWED_CARD_ITEM_KEYS = [:title, :description, :media_url, :actions].freeze
  ALLOWED_CARD_ITEM_ACTION_KEYS = [:text, :type, :payload, :uri].freeze
  ALLOWED_FORM_ITEM_KEYS = [:type, :placeholder, :label, :name, :options, :default, :required, :pattern, :title, :pattern_error].freeze
  ALLOWED_ARTICLE_KEYS = [:title, :description, :link].freeze

  def validate(record)
    case record.content_type
    when 'input_select'
      validate_items!(record)
      validate_item_attributes!(record, ALLOWED_SELECT_ITEM_KEYS)
    when 'cards'
      validate_items!(record)
      validate_cards!(record)
    when 'form'
      validate_items!(record)
      validate_item_attributes!(record, ALLOWED_FORM_ITEM_KEYS)
    when 'article'
      validate_items!(record)
      validate_item_attributes!(record, ALLOWED_ARTICLE_KEYS)
    end
  end

  private

  def validate_items!(record)
    record.errors.add(:content_attributes, 'At least one item is required.') if record.items.blank?
    record.errors.add(:content_attributes, 'Items should be a hash.') if record.items.reject { |item| item.is_a?(Hash) }.present?
  end

  def validate_item_attributes!(record, valid_keys)
    item_keys = record.items.collect(&:keys).flatten.filter_map(&:to_sym)
    invalid_keys = item_keys - valid_keys
    record.errors.add(:content_attributes, "contains invalid keys for items : #{invalid_keys}") if invalid_keys.present?
  end

  def validate_cards!(record)
    return if record.items.blank? || record.items.any? { |item| !item.is_a?(Hash) }

    record.items.each do |item|
      item = item.with_indifferent_access
      if %w[product order].include?(item[:type])
        validate_commerce_card!(record, item)
      else
        invalid_keys = item.keys.map(&:to_sym) - ALLOWED_CARD_ITEM_KEYS
        record.errors.add(:content_attributes, "contains invalid card keys: #{invalid_keys}") if invalid_keys.present?
        record.errors.add(:content_attributes, 'contains items missing actions') if item[:actions].blank?
        Array(item[:actions]).each do |action|
          invalid = action.keys.map(&:to_sym) - ALLOWED_CARD_ITEM_ACTION_KEYS
          record.errors.add(:content_attributes, "contains invalid action keys: #{invalid}") if invalid.present?
        end
      end
    end
  end

  def validate_commerce_card!(record, item)
    allowed = %w[type title product_id order_id price media_url action]
    invalid = item.keys - allowed
    record.errors.add(:content_attributes, "contains invalid card keys: #{invalid}") if invalid.present?
    fields = %w[title product_id order_id price media_url]
    unless fields.all? { |key| item[key].nil? || item[key].is_a?(String) }
      record.errors.add(:content_attributes, 'commerce card fields must be strings')
    end
    required = %w[title product_id media_url]
    required.concat(%w[order_id price]) if item[:type] == 'order'
    record.errors.add(:content_attributes, 'commerce card is missing required fields') if required.any? { |key| item[key].blank? }
    unless item[:media_url].to_s.match?(%r{\Ahttps?://[^\s]+\z}i)
      record.errors.add(:content_attributes, 'contains an invalid card image URL')
    end
    action = item[:action]
    return if action.blank?

    valid = action.is_a?(Hash) && case action[:type]
                                when 'url'
                                  action.keys.sort == %w[type url] && action[:url].to_s.match?(/\Ahttps?:\/\/[^\s]+\z/i)
                                when 'miniapp'
                                  action.keys.sort == %w[path type] && action[:path].to_s.match?(%r{\A/pages/[^\s]*\z})
                                else
                                  false
                                end
    record.errors.add(:content_attributes, 'contains an invalid card action') unless valid
  end
end
