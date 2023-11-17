## Roles and permissions

The actions that a user can take within a workspace is determined by its role. The following table summarizes the permissions for each role:

| Features                     | Viewers | Editors | Admins |
|------------------------------|---------|---------|--------|
| Read & download files        | x       | x       | x      |
| Write files                  | -       | x       | x      |
| View database content        | x       | x       | x      |
| View database credentials    | -       | x       | x      |
| Write to database            | -       | x       | x      |
| Regenerate database password | -       | -       | x      |
| Read & download datasets     | x       | x       | x      |
| Write datasets               | -       | x       | x      |
| Use connections              | -       | x       | x      |
| Manage connections           | -       | -       | x      |
| Launch pipelines             | x       | x       | x      |
| Create pipelines             | -       | x       | x      |
| Use notebooks                | -       | x       | x      |
| Update workspace description | -       | x       | x      |
| Manage & invite users        | -       | -       | x      |
