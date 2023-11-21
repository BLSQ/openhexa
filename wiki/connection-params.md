
## Using the workspace database

Reading from or writing to the workspace database can also be done using the `workspace` helper.

The following section will illustrate how to use it in a pipeline, for more information about the workspace database, please refer to the [Using the workspace database](https://github.com/BLSQ/openhexa/wiki/Using-the-OpenHexa-SDK#using-the-workspace-database) section of the SDK documentation.

Let's adapt our pipeline to write the transformed data to the workspace database, in addition to storing it as a CSV file.

First, you will need to have an up-and-running Postgres server on your work computer. When you push your pipeline to the Cloud, it will use the actual workspace database, but we need a local database for development (see the [official Postgres documentation](https://www.postgresql.org/download/) for installation instructions).

Then, create a database. If you use `psql`: 

```shell
CREATE DATABASE simple_etl;
```

Then, adapt you `workspace.yaml` file with the proper connection parameters in the `database` section.

You can then change your pipeline code:

```python
import json
from time import sleep
import pandas as pd

from openhexa.sdk import current_run, pipeline, workspace
from sqlalchemy import create_engine


@pipeline("simple-etl", name="Simple ETL")
def simple_etl():
    people_data = extract_people_data()
    activity_data = extract_activity_data()
    transformed_data = transform(people_data, activity_data)
    load(transformed_data)


@simple_etl.task
def extract_people_data():
    current_run.log_info("Extracting people data...")
    sleep(2)  # Let's pretend we are querying an external system

    return pd.DataFrame([{"id": 1, "first_name": "Mary", "last_name": "Johnson"},
                         {"id": 2, "first_name": "Peter", "last_name": "Jackson"},
                         {"id": 3, "first_name": "Taylor", "last_name": "Smith"}]).set_index("id")


@simple_etl.task
def extract_activity_data():
    current_run.log_info(f"Extracting activity data...")
    with open(f"{workspace.files_path}/activities.json", "r") as activities_file:
        return pd.DataFrame(json.load(activities_file)["activities"]).set_index("id")


@simple_etl.task
def transform(people_data, activity_data):
    current_run.log_info(f"Transforming data...")
    combined_df = activity_data.join(people_data, on="person").reset_index()

    return combined_df


@simple_etl.task
def load(transformed_data):
    current_run.log_info(f"Loading data ({len(transformed_data)} records)")

    output_path = f"{workspace.files_path}/transformed.csv"
    transformed_data.to_csv(output_path)
    current_run.add_file_output(output_path)

    engine = create_engine(workspace.database_url)
    transformed_data.to_sql("transformed", if_exists="replace", con=engine)
    current_run.add_database_output("transformed")


if __name__ == "__main__":
    simple_etl()
```

Run the pipeline using `python pipeline.py`, and you can then query your local database:

```sql
SELECT * FROM transformed;
```


In this example, we used `pandas.Dataframe.to_sql` method to write data on the workspace database. By default, all rows will be written at once. When dealing with large data it can become quickly an issue and thus we encourage the usage of `chunksize` argument to specify the number of rows to be written per batch. The `dtype` argument can also be used to specify the columns data type for more data integrity. If you don't, pandas will try to guess the database dtype from the pandas dtype and it can lead to a lot of issues (e.g. float can become text).

If all goes well, you should see the transformed data in the table content.


###############################
##############

### Parameters


As you can see, adding parameter to your pipeline is as simple as decorating your pipeline function with the `@parameter` decorator.

This decorator requires a `code` as its first argument: this will be used as the argument passed to the pipeline function.

The `@parameter` decorator also requires the `type` keyword argument, which should be a basic Python scalar type (`int`, `float`, `str` or `bool`).

The `@parameter` can be also of type connection
- `DHIS2Connection`
- `PostgreSQLConnection`
- `IASOConnection`
- `S3Connection`
- `GCSConnection`

If the parameter type is one of the listed above, the corresponding connection instance will be automatically injected (with `workspace.yaml` file on local environment and the actual connections configured within the workspace online).
Connection parameters allows to write flexible pipeline that can be used in different environment: dev, staging, production.

The following keyword arguments are optional:
- `name`: A human-readable name to be used for the form label in the web interface
- `help`: An additional help text to be displayed in the form
- `choices`: A list of valid values accepted for the parameter
- `default`: an optional default value
- `required`: whether the parameter is required, `True` by default
- `multiple` whether the arguments should accept a list of values rather than a single value, `False` by default

Note that, unlike the other types, a `connection parameter` cannot be multiple or accept choices.



Now that our pipeline accepts parameter, let's run it with a valid configuration. The pipeline runner expects the configuration to be provided as a valid JSON string using the `-c` argument:

```shell
python pipeline.py -c '{"user_ids": [1, 2, 3], "activity_name": "Activity 2"}'
python pipeline.py -c '{"user_ids": [2], "anonymize": false}'
```

Typing the JSON config manually everytime can be tedious, so the runner also accepts a `-f` argument that allows you to specify the path to a JSON config file:

```shell
echo '{"user_ids": [1, 2, 3], "activity_name": "Activity 2"}' > sample_config.json
python pipeline.py -f sample_config.json
```

Great! Let's push this pipeline to the cloud so that we can run it with the web interface.


<img width="618" alt="Screenshot 2023-04-28 at 16 35 15" src="https://user-images.githubusercontent.com/690667/235177316-4208df73-ec63-46ad-9cc3-1cef9d19e5c3.png">

Another example of pipeline with connection parameters:

```python
import hashlib
import json
from time import sleep
import pandas as pd

from openhexa.sdk import current_run, pipeline, workspace, parameter
from openhexa.sdk.workspaces.connection import PostgreSQLConnection
from sqlalchemy import create_engine


@pipeline("simple-etl", name="Simple ETL")
@parameter("user_ids", name="User IDs", type=int, multiple=True)
@parameter(
    "activity_name",
    name="Activity name",
    choices=["Activity 1", "Activity 2", "Activity 3"],
    type=str,
    required=False
)
@parameter("anonymize", name="Anonymize data", help="Hash the user first and last names", type=bool, default=True)
@parameter("postgres_connection", name="Postgres Connection identifier", type=PostgreSQLConnection, required=True)
def simple_etl(user_ids, activity_name, anonymize, postgres_connection):
    people_data = extract_people_data(user_ids)
    activity_data = extract_activity_data(activity_name)
    transformed_data = transform(people_data, activity_data, anonymize)
    load(transformed_data, postgres_connection)


@simple_etl.task
def extract_people_data(user_ids):
    current_run.log_info(f"Extracting people data (ids {','.join(str(uid) for uid in user_ids)})...")
    sleep(2)  # Let's pretend we are querying an external system

    df = pd.DataFrame([{"id": 1, "first_name": "Mary", "last_name": "Johnson"},
                       {"id": 2, "first_name": "Peter", "last_name": "Jackson"},
                       {"id": 3, "first_name": "Taylor", "last_name": "Smith"}])
    df = df[df["id"].isin(user_ids)]

    return df.set_index("id")


@simple_etl.task
def extract_activity_data(activity_name):
    current_run.log_info(f"Extracting activity data ({activity_name if activity_name is not None else 'all'})...")
    with open(f"{workspace.files_path}/activities.json", "r") as activities_file:
        df = pd.DataFrame(json.load(activities_file)["activities"])

    if activity_name is not None:
        df = df[df["activity"] == activity_name]

    return df.set_index("id")


@simple_etl.task
def transform(people_data, activity_data, anonymize):
    current_run.log_info(f"Transforming data ({'anonymized' if anonymize else 'not anonymized'})...")
    combined_df = activity_data.join(people_data, on="person").reset_index()

    combined_df["user"] = combined_df["first_name"] + " " + combined_df["last_name"]
    if anonymize:
        combined_df["user"] = combined_df["user"].apply(lambda u: hashlib.sha256(u.encode("utf-8")).hexdigest())
    combined_df = combined_df.drop(columns=["first_name", "last_name"])

    return combined_df


@simple_etl.task
def load(transformed_data, postgres_connection):
    current_run.log_info(f"Loading data ({len(transformed_data)} records)")

    output_path = f"{workspace.files_path}/transformed.csv"
    transformed_data.to_csv(output_path)
    current_run.add_file_output(output_path)

    engine = create_engine(postgres_connection.url)
    transformed_data.to_sql("transformed", if_exists="replace", con=engine)
    current_run.add_database_output("transformed")


if __name__ == "__main__":
    simple_etl()
```

On the web interface, select the corresponding connection name :


<img width="618" alt="Screenshot 2023-11-21 at 12 38 15" src="https://github.com/BLSQ/openhexa-app/assets/25453621/d20552e6-c3e6-4f15-9f25-86ea4c2dca98">
