# LeaveBoard Self-Hosting

Deploy LeaveBoard on your own infrastructure.

## Quick Start

```bash
chmod +x install.sh
./install.sh
```

## Manual Setup

1. Copy `.env.example` to `.env`
2. Update the configuration values
3. Run `docker compose up -d`

## Services

| Service | Port | Description |
|---------|------|-------------|
| API | 3080 | Main application API |
| PostgreSQL | 5432 | Database |
| Redis | 6379 | Cache/Sessions |
| Web | 80 | Frontend (optional) |

## Configuration

Edit `.env` to configure:

- **DB_PASSWORD**: Database password (required)
- **JWT_SECRET**: JWT signing secret (required)
- **SMTP_***: Email settings for notifications

## Backup

```bash
# Backup database
docker exec leaveboard-db pg_dump -U leaveboard leaveboard > backup.sql

# Restore database
cat backup.sql | docker exec -i leaveboard-db psql -U leaveboard leaveboard
```

## Updating

```bash
docker compose pull
docker compose up -d
```

## Support

For issues, check the logs:

```bash
docker compose logs -f
```
