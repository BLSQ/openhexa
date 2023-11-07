## Roles and permissions

Roles let you manage who can do what in a workspace. Each user added to a workspace, is also assigned to a role.
The table below show the mapping between each features and roles.


|  Features           |  `VIEWER`             |`EDITOR`               |`ADMIN`               |
| ------------------- | --------------------- | --------------------- | ---------------------|
| Files    | Read  | Read / Write | Read / Write|
| Database   | Read (limited : cannot read database credentials)| Read / Write| Read / Write |
| Datasets   | - | Read / Write| Read / Write |
| Connections    | Read | Read / Write | Read / Write|
| Pipelines    | Read | Read / Write | Read / Write|
| Notebooks   |- |Read / Write (limited : only workspace description) | Read / Write|
| Workspace  Settings   |- |Read / Write (limited : only workspace description) | Read / Write|
