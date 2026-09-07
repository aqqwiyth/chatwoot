json.id resource.id
json.content resource.content
json.message_type resource.message_type_before_type_cast
json.content_type resource.content_type
json.content_attributes resource.content_attributes
json.external_event_id resource.external_event_id
json.extensions resource.extensions
json.actor resource.extensions['actor'] if resource.extensions.is_a?(Hash) && resource.extensions['actor'].present?
json.created_at resource.created_at.to_i
json.conversation_id resource.conversation.display_id
json.attachments resource.attachments.map(&:push_event_data) if resource.attachments.present?
json.sender resource.sender.push_event_data if resource.sender
