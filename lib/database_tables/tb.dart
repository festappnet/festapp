class Tb {
  static OccasionsTb occasions = const OccasionsTb();
  static OccasionUsersTb occasion_users = const OccasionUsersTb();
  static NewsTb news = const NewsTb();
  static UserInfoTb user_info = const UserInfoTb();
  static UserNewsTb user_news = const UserNewsTb();
  static InformationTb information = const InformationTb();
  static InformationHidden information_hidden = const InformationHidden();
  static EventsTb events = const EventsTb();
  static EventUserTb event_users = const EventUserTb();
  static EventUsersSavedTb event_users_saved = const EventUsersSavedTb();
  static EventGroupsTb event_groups = const EventGroupsTb();
  static ExclusiveGroupTb exclusive_groups = const ExclusiveGroupTb();
  static ExclusiveEventsTb exclusive_events = const ExclusiveEventsTb();
  static PlacesTb places = const PlacesTb();
  static UserGroupsTb user_groups = const UserGroupsTb();
  static UserGroupInfoTb user_group_info = const UserGroupInfoTb();
  static LogNotificationsTb log_notifications = const LogNotificationsTb();
  static EventRolesTb event_roles = const EventRolesTb();
  static RoleInfoTb role_info = const RoleInfoTb();
  static UserCompanionsTb user_companions = const UserCompanionsTb();
  static IconsTb icons = const IconsTb();
  static PlaceTypesTb place_types = const PlaceTypesTb();
  static OrganizationsTb organizations = const OrganizationsTb();
  static OrganizationUsersTb organization_users = const OrganizationUsersTb();
  static FormsTb forms = const FormsTb();
  static FormFieldsTb form_fields = const FormFieldsTb();
  static UnitsTb units = const UnitsTb();
  static UnitUsersTb unit_users = const UnitUsersTb();
  static ImagesTb images = const ImagesTb();
  static EmailTemplatesTb email_templates = const EmailTemplatesTb();
  static PathGroupsTb path_groups = const PathGroupsTb();
  static ActivitiesTb activities = const ActivitiesTb();
  static ActivityAssignmentsTb activity_assignments =
      const ActivityAssignmentsTb();
  static ActivityAssignmentPlacesTb activity_assignment_places =
      const ActivityAssignmentPlacesTb();
  static ActivityAssignmentEventsTb activity_assignment_events =
      const ActivityAssignmentEventsTb();

  // New tables based on the updated schema
  static InventoryPoolsTb inventory_pools = const InventoryPoolsTb();
  static ResourcesTb resources = const ResourcesTb();
  static ResourceSlotsTb resource_slots = const ResourceSlotsTb();
  static InventoryContextsTb inventory_contexts = const InventoryContextsTb();
  static ProductsTb products =
      const ProductsTb(); // Assuming a products class is needed
}

class OccasionsTb {
  const OccasionsTb();
  String get table => "occasions";
  String get id => "id";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get organization => "organization";
  String get unit => "unit";
  String get is_hidden => "is_hidden";
  String get start_time => "start_time";
  String get end_time => "end_time";
  String get is_open => "is_open";
  String get is_promoted => "is_promoted";
  String get link => "link";
  String get title => "title";
  String get description => "description";
  String get features => "features";
  String get place => "place";
  String get data => "data";
  String get data_defaultMapZoom => "defaultMapZoom";
  String get data_defaultMapLocation => "defaultMapLocation";
  String get data_events_registration_start => "events_registration_start";
  String get data_image => "image";

  // Map layer keys as nested object
  String get data_map_layer => "map_layer";
  String get data_map_layer_layer_link => "layer_link";
  String get data_map_layer_logo => "logo";
  String get data_map_layer_text => "text";
  String get data_map_layer_logo_link => "logo_link";
  String get data_map_layer_text_link => "text_link";

  // Game settings keys
  String get data_game => "game";
  String get data_game_start => "start";
  String get data_game_end => "end";

  String get services => "services";
  String get data_features_code => "code";
  String get data_features_is_enabled => "is_enabled";

  String get data_timezone => "timezone";
  String get data_reply_to => "reply_to";
  // Legacy - deadline config now stored in deposit feature (features JSONB)
  String get data_surcharge_deadline_days => "surcharge_deadline_days";
  String get data_surcharge_deadline => "surcharge_deadline";
}

class OccasionUsersTb {
  const OccasionUsersTb();
  String get table => "occasion_users";
  String get occasion => "occasion";
  String get created_at => "created_at";
  String get user => "user";
  String get is_editor_view => "is_editor_view";
  String get is_editor_order => "is_editor_order";
  String get is_editor_order_view => "is_editor_order_view";
  String get is_cleaning_crew => "is_cleaning_crew";
  String get is_cleaning_blocked => "is_cleaning_blocked";
  String get is_receptionist => "is_receptionist";
  String get is_editor => "is_editor";
  String get is_manager => "is_manager";
  String get is_approved => "is_approved";
  String get is_approver => "is_approver";
  String get role => "role";
  String get data => "data";
  String get data_email => "email";
  String get data_name => "name";
  String get data_surname => "surname";
  String get data_sex => "sex";
  String get data_birthDate => "birthDate";
  String get data_phone => "phone";
  String get data_appLinksSent => "app_links_sent";
  String get data_is_volunteer => "is_volunteer";
  String get data_note => "note";
  String get data_diet => "diet";
  String get data_text1 => "text1";
  String get data_text2 => "text2";
  String get data_text3 => "text3";
  String get data_text4 => "text4";
  String get services => "services";
  String get services_accommodation => "services_accommodation";
  String get services_food => "services_food";
}

class NewsTb {
  const NewsTb();
  String get table => "news";
  String get id => "id";
  String get occasion => "occasion";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get created_by => "created_by";
  String get message => "message";
}

class UserNewsTb {
  const UserNewsTb();
  String get table => "user_news";
  String get occasion => "occasion";
  String get created_at => "created_at";
  String get news_id => "news_id";
  String get user => "user";
  String get message => "message";
}

class UserInfoTb {
  const UserInfoTb();
  String get table => "user_info";
  String get id => "id";
  String get organization => "organization";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get email_readonly => "email_readonly";
  String get email_delivery => "email_delivery";
  String get name => "name";
  String get surname => "surname";
  String get sex => "sex";
  String get phone => "phone";
  String get role => "role";
  String get birth_date => "birth_date";
  String get is_editor_readonly => "is_editor_readonly";
  String get is_admin_readonly => "is_admin_readonly";
  String get data => "data";
}

class RoleInfoTb {
  const RoleInfoTb();
  String get table => "role_info";
  String get id => "id";
  String get title => "title";
  String get occasion => "occasion";
}

class EventRolesTb {
  const EventRolesTb();
  String get table => "event_roles";
  String get event => "event";
  String get role => "role";
}

class InformationTb {
  const InformationTb();
  String get table => "information";
  String get id => "id";
  String get occasion => "occasion";
  String get unit => "unit";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get is_hidden => "is_hidden";
  String get title => "title";
  String get type => "type";
  String get description => "description";
  String get order => "order";
  String get information_hidden => "information_hidden";
  String get data => "data";
  String get data_correct => "correct";
  String get data_correct_reference => "correct_reference";
  String get data_date => "date";
}

class InformationHidden {
  const InformationHidden();
  String get table => "information_hidden";
  String get occasion => "occasion";
  String get id => "id";
  String get data => "data";
  String get data_correct => "correct";
}

class EventsTb {
  const EventsTb();
  String get table => "events";
  String get id => "id";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get occasion => "occasion";
  String get is_hidden => "is_hidden";
  String get title => "title";
  String get start_time => "start_time";
  String get end_time => "end_time";
  String get max_participants => "max_participants";
  String get description => "description";
  String get place => "place";
  String get split_for_men_women => "split_for_men_women";
  String get is_group_event => "is_group_event";
  String get type => "type";
  String get data => "data";

  String get dataHeaderImage => "header_image";
  String get dataIsCancelled => "is_cancelled";
}

class EventUserTb {
  const EventUserTb();
  String get table => "event_users";
  String get created_at => "created_at";
  String get event => "event";
  String get user => "user";
}

class EventUsersSavedTb {
  const EventUsersSavedTb();
  String get table => "event_users_saved";
  String get created_at => "created_at";
  String get event => "event";
  String get user => "user";
}

class EventGroupsTb {
  const EventGroupsTb();
  String get table => "event_groups";
  String get event_parent => "event_parent";
  String get event_child => "event_child";
}

class ExclusiveGroupTb {
  const ExclusiveGroupTb();
  String get table => "exclusive_groups";
  String get id => "id";
  String get occasion => "occasion";
  String get title => "title";
}

class ExclusiveEventsTb {
  const ExclusiveEventsTb();
  String get table => "exclusive_events";
  String get event => "event";
  String get group => "group";
}

class PlacesTb {
  const PlacesTb();
  String get table => "places";
  String get id => "id";
  String get occasion => "occasion";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get is_hidden => "is_hidden";
  String get title => "title";
  String get description => "description";
  String get type => "type";
  String get coordinates => "coordinates";
  String get order => "order";
  String get icon => "icon";
}

class UserGroupInfoTb {
  const UserGroupInfoTb();
  String get table => "user_group_info";
  String get id => "id";
  String get occasion => "occasion";
  String get title => "title";
  String get place => "place";
  String get description => "description";
  String get type => "type";
  String get data => "data";
}

class UserGroupsTb {
  const UserGroupsTb();
  String get table => "user_groups";
  String get user => "user";
  String get group => "group";
  String get is_admin => "is_admin";
}

class LogNotificationsTb {
  const LogNotificationsTb();
  String get table => "log_notifications";
  String get id => "id";
  String get occasion => "occasion";
  String get organization => "organization";
  String get created_at => "created_at";
  String get user_id => "user_id";
  String get heading => "heading";
  String get content => "content";
  String get to => "to";
}

class UserCompanionsTb {
  const UserCompanionsTb();
  String get table => "user_companions";
  String get user => "user";
  String get companion => "companion";
}

class IconsTb {
  const IconsTb();
  String get table => "icons";
  String get id => "id";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get organization => "organization";
  String get unit => "unit";
  String get created_by => "created_by";
  String get link => "link";
  String get data => "data";
}

class PlaceTypesTb {
  const PlaceTypesTb();
  String get table => "place_types";
  String get id => "id";
  String get occasion => "occasion";
  String get code => "code";
  String get title => "title";
  String get icon => "icon";
  String get order => "order";
  String get is_hidden => "is_hidden";
  String get is_default => "is_default";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
}

class OrganizationsTb {
  const OrganizationsTb();
  String get table => "organizations";
  String get id => "id";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get title => "title";
  String get data => "data";
}

class OrganizationUsersTb {
  const OrganizationUsersTb();
  String get table => "organization_users";
  String get id => "id";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get organization => "organization";
  String get user => "user";
  String get is_admin => "is_admin";
}

class FormsTb {
  const FormsTb();
  String get table => "forms";
  String get id => "id";
  String get created_at => "created_at";
  String get data => "data";
  String get key => "key";
  String get title => "title";
  String get occasion => "occasion";
  String get blueprint => "blueprint";
  String get type => "type";
  String get bank_account => "bank_account";
  String get deadline_duration_seconds => "deadline_duration_seconds";
  String get is_open => "is_open";
  String get header => "header";
  String get header_off => "header_off";
  String get link => "link";
}

class FormFieldsTb {
  const FormFieldsTb();
  String get table => "form_fields";
  String get id => "id";
  String get created_at => "created_at";
  String get title => "title";
  String get description => "description";
  String get data => "data";
  String get type => "type";
  String get is_required => "is_required";
  String get form => "form";
  String get is_hidden => "is_hidden";
  String get order => "order";
  String get product_type => "product_type";
  String get product_type_data => "product_type_data";
  String get is_ticket_field => "is_ticket_field";
}

class UnitsTb {
  const UnitsTb();
  String get table => "units";
  String get id => "id";
  String get created_at => "created_at";
  String get title => "title";
  String get organization => "organization";
  String get features => "features";
  String get data => "data";
  String get data_reply_to => "reply_to";
  String get data_communication_tone => "communication_tone";
}

class UnitUsersTb {
  const UnitUsersTb();
  String get table => "unit_users";
  String get created_at => "created_at";
  String get unit => "unit";
  String get user => "user";
  String get is_manager => "is_manager";
  String get is_editor => "is_editor";
  String get is_editor_view => "is_editor_view";
  String get data => "data";
}

class ImagesTb {
  const ImagesTb();
  String get table => "images";
  String get id => "id";
  String get link => "link";
  String get occasion => "occasion";
  String get unit => "unit";
}

class EmailTemplatesTb {
  const EmailTemplatesTb();
  String get table => "email_templates";
  String get id => "id";
  String get html => "html";
  String get occasion => "occasion";
  String get subject => "subject";
  String get organization => "organization";
  String get code => "code";
  String get unit => "unit";
  String get title => "title";
}

class PathGroupsTb {
  const PathGroupsTb();
  String get table => "path_groups";
  String get id => "id";
  String get is_hidden => "is_hidden";
  String get title => "title";
  String get path_data => "path_data";
  String get data => "data";
  String get icon => "icon";
  String get color => "color";
  String get occasion => "occasion";
  String get order => "order";
}

class ActivitiesTb {
  const ActivitiesTb();
  String get table => 'activities';
  String get id => 'id';
  String get created_at => 'created_at';
  String get updated_at => 'updated_at';
  String get title => 'title';
  String get description => 'description';
  String get type => 'type';
  String get occasion => 'occasion';
  String get unit => 'unit';
  String get is_hidden => 'is_hidden';
  String get data => 'data';
  String get order => 'order';
}

class ActivityAssignmentsTb {
  const ActivityAssignmentsTb();
  String get table => 'activity_assignments';
  String get id => 'id';
  String get activity_id => 'activity_id';
  String get user => 'user';
  String get start_time => 'start_time';
  String get end_time => 'end_time';
  String get title => 'title';
  String get description => 'description';
  String get data => 'data';
}

class ActivityAssignmentPlacesTb {
  const ActivityAssignmentPlacesTb();
  String get table => 'activity_assignment_places';
  String get assignment_id => 'assignment_id';
  String get place_id => 'place_id';
}

class ActivityAssignmentEventsTb {
  const ActivityAssignmentEventsTb();
  String get table => 'activity_assignment_events';
  String get assignment_id => 'assignment_id';
  String get event_id => 'event_id';
}

class InventoryPoolsTb {
  const InventoryPoolsTb();
  String get table => "inventory_pools";
  String get id => "id";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get data => "data";
  String get title => "title";
  String get sellable_capacity => "sellable_capacity";
  String get occasion => "occasion";
  String get type => "type";
  String get description => "description";
  String get data_is_auto_resource_assignment => "is_auto_resource_assignment";
  String get data_place_id => "place_id";
}

class ResourcesTb {
  const ResourcesTb();
  String get table => "resources";
  String get id => "id";
  String get created_at => "created_at";
  String get updated_at => "updated_at";
  String get title => "title";
  String get description => "description";
  String get capacity => "capacity";
  String get booking_rules => "booking_rules";
  String get inventory_pool => "inventory_pool";
  String get place => "place";
  String get occasion => "occasion";
  String get unit => "unit";
  String get data => "data";
}

class ResourceSlotsTb {
  const ResourceSlotsTb();
  String get table => "resource_slots";
  String get id => "id";
  String get resource => "resource";
  String get title => "title";
  String get data => "data";
}

class InventoryContextsTb {
  const InventoryContextsTb();
  String get table => "inventory_contexts";
  String get id => "id";
  String get inventory_pool => "inventory_pool";
  String get block_date => "block_date";
  String get title => "title";
  String get order => "order";
  String get data => "data";
  String get data_product_id => "product_id";
}

class ProductsTb {
  const ProductsTb();
  String get table => "products";
  String get id => "id";
  String get title => "title";
  String get price => "price";
  String get data => "data";
  String get occasion => "occasion";
}
