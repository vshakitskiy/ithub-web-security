# Laboratory Work 1

Authentication API with JWT tokens, rate limiting, and password recovery.

## Requirements

- **Gleam** - [gleam.run](https://gleam.run)
- **direnv** - [direnv.net](https://direnv.net)

## Setup

```sh
gleam deps download
direnv allow
gleam run
```

## Endpoints

### Public

**POST /auth/register**
```json
{
  "username": "string",
  "email": "string",
  "password": "string"
}
```

**POST /auth/login**

Rate limited: 3 attempts per 60 seconds per IP.
```json
{
  "username": "string",
  "password": "string"
}
```
Returns: `{"token": "...", "user": {...}}`

**POST /auth/forgot_password**
```json
{
  "email": "string"
}
```
Returns recovery token.

**POST /auth/reset_password**
```json
{
  "token": "string",
  "new_password": "string"
}
```

### Protected

Requires `Authorization: Bearer <token>` header.

**POST /auth/logout**

No body required.

**GET /api/profile**

Returns current user data.

### Admin

Requires `Authorization: Bearer <token>` header with admin role.

**GET /admin/users**

Returns list of all users.

## Environment

Configuration is in `.envrc`:

- `JWT_SECRET` - Secret for signing tokens
- `JWT_EXPIRY_MINUTES` - Token lifetime (default: 15)
- `RATE_LIMIT_ATTEMPTS` - Max login attempts (default: 3)
- `RATE_LIMIT_WINDOW_SECONDS` - Rate limit window (default: 60)
- `PORT` - Server port (default: 8080)
