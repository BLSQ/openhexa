## Roles and permissions

Roles let you manage who can do what in a workspace. Each user added to a workspace, is also assigned to a role.
The table below show the mapping between each features and roles.


| Features            | `VIEWER`                                          | `EDITOR`                                             | `ADMIN`       |
|---------------------|---------------------------------------------------|------------------------------------------------------|---------------|
| Files               | Read                                              | Read / Write                                         | Re ad / Write |
| Database            | Read (limited : cannot read database credentials) | Read / Write                                         | Read / Write  |
| Datasets            | -                                                 | Read / Write                                         | Read / Write  |
| Connections         | Read                                              | Read / Write                                         | Read / Write  |
| Pipelines           | Read                                              | Read / Write                                         | Read / Write  |
| Notebooks           | -                                                 | Read / Write (limited : only workspace description)  | Read / Write  |
| Workspace  Settings | -                                                 | Read / Write (limited : only workspace description)  | Read / Write  |

The actions that a user can take within a workspace is determined by its role. The following table summarizes the permissions for each role:

| Features                     | Viewers | Editors | Admins |
|------------------------------|---------|---------|--------|
| Read files                   | x       | x       | x      |
| Write files                  | -       | x       | x      |
| View database content        | x       | x       | x      |
| View database credentials    | -       | x       | x      |
| Write to database            | -       | x       | x      |
| Regenerate database password | -       | -       | x      |
| Read datasets                | x       | x       | x      |
| Write datasets               | -       | x       | x      |
| Use connections              | -       | x       | x      |
| Manage connections           | -       | -       | x      |
| Launch pipelines             | x       | x       | x      |
| Create pipelines             | -       | x       | x      |
| Use notebooks                | -       | x       | x      |
| Manage & invite users        | -       | x       | x      |
| Update workspace description | -       | x       | x      |
