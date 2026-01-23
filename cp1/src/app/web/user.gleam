import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import storail

// User
// -----------------------------------------------------------------------------

pub type User {
  User(
    id: String,
    username: String,
    email: String,
    password_hash: String,
    role: Role,
    created_at: Timestamp,
  )
}

pub fn user_to_public_json(user: User) -> json.Json {
  json.object([
    #("id", json.string(user.id)),
    #("username", json.string(user.username)),
    #("email", json.string(user.email)),
    #("role", json.string(role_to_string(user.role))),
    #(
      "created_at",
      json.int({
        timestamp.to_unix_seconds_and_nanoseconds(user.created_at)
        |> pair.first
      }),
    ),
  ])
}

fn user_to_json(user: User) -> json.Json {
  json.object([
    #("id", json.string(user.id)),
    #("username", json.string(user.username)),
    #("email", json.string(user.email)),
    #("password_hash", json.string(user.password_hash)),
    #("role", json.string(role_to_string(user.role))),
    #(
      "created_at",
      json.int({
        timestamp.to_unix_seconds_and_nanoseconds(user.created_at)
        |> pair.first
      }),
    ),
  ])
}

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.string)
  use username <- decode.field("username", decode.string)
  use email <- decode.field("email", decode.string)
  use password_hash <- decode.field("password_hash", decode.string)
  use role <- decode.field("role", role_decoder())
  use created_at_seconds <- decode.field("created_at", decode.int)

  decode.success(User(
    id: id,
    username: username,
    email: email,
    password_hash: password_hash,
    role: role,
    created_at: timestamp.from_unix_seconds(created_at_seconds),
  ))
}

// Role
// -----------------------------------------------------------------------------

pub type Role {
  UserRole
  ModeratorRole
  AdminRole
}

fn role_decoder() -> decode.Decoder(Role) {
  use role <- decode.then(decode.string)
  case role {
    "user" -> decode.success(UserRole)
    "moderator" -> decode.success(ModeratorRole)
    "admin" -> decode.success(AdminRole)
    _ -> decode.failure(AdminRole, "role")
  }
}

pub fn role_to_string(role: Role) -> String {
  case role {
    UserRole -> "user"
    ModeratorRole -> "moderator"
    AdminRole -> "admin"
  }
}

pub fn string_to_role(role: String) -> Result(Role, Nil) {
  case role {
    "user" -> Ok(UserRole)
    "moderator" -> Ok(ModeratorRole)
    "admin" -> Ok(AdminRole)
    _ -> Error(Nil)
  }
}

// Collection
// -----------------------------------------------------------------------------

pub type UserCollection =
  storail.Collection(User)

pub type UserError {
  StoreError(String)
  NotFound
  AlreadyExists
  ValidationError(String)
}

pub fn init_collection(storage_path: String) -> UserCollection {
  storail.Collection(
    name: "users",
    to_json: user_to_json,
    decoder: user_decoder(),
    config: storail.Config(storage_path: storage_path),
  )
}

pub fn save(collection: UserCollection, user: User) -> Result(Nil, UserError) {
  storail.key(collection, user.id)
  |> storail.write(user)
  |> result.replace_error(StoreError("Failed to save user"))
}

pub fn get_by_id(
  collection: UserCollection,
  id: String,
) -> Result(User, UserError) {
  storail.key(collection, id)
  |> storail.read
  |> result.replace_error(NotFound)
}

pub fn get_by_username(
  collection: UserCollection,
  username: String,
) -> Result(User, UserError) {
  use namespace <- result.try(
    storail.list(collection, [])
    |> result.replace_error(StoreError("Failed to list users")),
  )

  list.find_map(namespace, fn(id) {
    case get_by_id(collection, id) {
      Ok(user) if user.username == username -> Ok(user)
      _ -> Error(Nil)
    }
  })
  |> result.replace_error(NotFound)
}

pub fn get_by_email(
  collection: UserCollection,
  email: String,
) -> Result(User, UserError) {
  use namespace <- result.try(
    storail.list(collection, [])
    |> result.replace_error(StoreError("Failed to list users")),
  )

  list.find_map(namespace, fn(id) {
    case get_by_id(collection, id) {
      Ok(user) if user.email == email -> Ok(user)
      _ -> Error(Nil)
    }
  })
  |> result.replace_error(NotFound)
}

pub fn list_all(collection: UserCollection) -> Result(List(User), UserError) {
  use ids <- result.try(
    storail.list(collection, [])
    |> result.replace_error(StoreError("Failed to list users")),
  )

  list.map(ids, get_by_id(collection, _))
  |> result.all
}

// Validation
// -----------------------------------------------------------------------------

pub fn validate_username(username: String) -> Result(Nil, String) {
  case string.length(username) {
    len if len < 3 -> Error("Username must be at least 3 characters")
    len if len > 20 -> Error("Username must be at most 20 characters")
    _ ->
      case string.contains(username, " ") {
        True -> Error("Username cannot contain spaces")
        False -> Ok(Nil)
      }
  }
}

pub fn validate_email(email: String) -> Result(Nil, String) {
  case string.contains(email, "@") && string.contains(email, ".") {
    True -> Ok(Nil)
    False -> Error("Invalid email format")
  }
}

pub fn validate_password_strength(password: String) -> Result(Nil, String) {
  case string.length(password) {
    len if len < 8 -> Error("Password must be at least 8 characters")
    _ -> Ok(Nil)
  }
}

pub fn has_role(user: User, allowed_roles: List(Role)) -> Bool {
  list.contains(allowed_roles, user.role)
}
