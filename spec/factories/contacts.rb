# frozen_string_literal: true

FactoryBot.define do
  factory :contact do
    sequence(:name) { |n| "Contact #{n}" }
    account

    trait :with_avatar do
      avatar { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }
    end

    trait :with_email do
      sequence(:email) { |n| "contact-#{n}@example.com" }
    end

    trait :with_phone_number do
      phone_number { Faker::PhoneNumber.cell_phone_in_e164 }
    end

    trait :group do
      contact_type { :group }
      sequence(:name) { |n| "Group #{n}" }
      extensions do
        {
          'schema_version' => 1,
          'provider' => 'feishu',
          'external_group_id' => "group-#{SecureRandom.hex(4)}"
        }
      end
    end
  end
end
