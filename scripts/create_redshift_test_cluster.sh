#!/usr/bin/env bash
# Creates the Redshift cluster with TICKIT sample data used by test/sql/redshift/*.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
# PREFIX keeps resource names unique in a shared account.
PREFIX="${PREFIX:-vi}"
CLUSTER="$PREFIX-redshift-$AWS_DEFAULT_REGION"
ROLE="$CLUSTER-tickit-loader"

# COPY needs a role that can read the public s3://redshift-downloads bucket.
ROLE_ARN=$(aws iam get-role --role-name "$ROLE" --query Role.Arn --output text 2>/dev/null) ||
	ROLE_ARN=$(aws iam create-role --role-name "$ROLE" --query Role.Arn --output text \
	--assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"redshift.amazonaws.com"},"Action":"sts:AssumeRole"}]}')
aws iam put-role-policy --role-name "$ROLE" --policy-name tickit-read \
	--policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:ListBucket"],"Resource":["arn:aws:s3:::redshift-downloads","arn:aws:s3:::redshift-downloads/*"]}]}'

# aws redshift create-cluster --cluster-identifier "$CLUSTER" --node-type ra3.large --cluster-type single-node \
# 	--db-name dev --master-username awsuser --manage-master-password --publicly-accessible \
# 	--iam-roles "$ROLE_ARN" --default-iam-role-arn "$ROLE_ARN" >/dev/null
# The cluster uses the default VPC security group, which blocks inbound traffic from outside the VPC.
# aws ec2 authorize-security-group-ingress --group-name default --protocol tcp --port 5439 \
# 	--cidr "$(curl -fsS https://checkip.amazonaws.com)/32" \
# 	--tag-specifications 'ResourceType=security-group-rule,Tags=[{Key=Name,Value='"$CLUSTER"'}]' >/dev/null
# aws redshift wait cluster-available --cluster-identifier "$CLUSTER"

C="iam_role default region 'us-east-1'"
S3="s3://redshift-downloads/tickit"
ID=$(aws redshift-data batch-execute-statement --cluster-identifier "$CLUSTER" --database dev --db-user awsuser \
	--query Id --output text --sqls \
	"create table users(userid integer not null distkey sortkey, username char(8), firstname varchar(30), lastname varchar(30), city varchar(30), state char(2), email varchar(100), phone char(14), likesports boolean, liketheatre boolean, likeconcerts boolean, likejazz boolean, likeclassical boolean, likeopera boolean, likerock boolean, likevegas boolean, likebroadway boolean, likemusicals boolean)" \
	"create table venue(venueid smallint not null distkey sortkey, venuename varchar(100), venuecity varchar(30), venuestate char(2), venueseats integer)" \
	"create table category(catid smallint not null distkey sortkey, catgroup varchar(10), catname varchar(10), catdesc varchar(50))" \
	"create table date(dateid smallint not null distkey sortkey, caldate date not null, day character(3) not null, week smallint not null, month character(5) not null, qtr character(5) not null, year smallint not null, holiday boolean default('N'))" \
	"create table event(eventid integer not null distkey, venueid smallint not null, catid smallint not null, dateid smallint not null sortkey, eventname varchar(200), starttime timestamp)" \
	"create table listing(listid integer not null distkey, sellerid integer not null, eventid integer not null, dateid smallint not null sortkey, numtickets smallint not null, priceperticket decimal(8,2), totalprice decimal(8,2), listtime timestamp)" \
	"create table sales(salesid integer not null, listid integer not null distkey, sellerid integer not null, buyerid integer not null, eventid integer not null, dateid smallint not null sortkey, qtysold smallint not null, pricepaid decimal(8,2), commission decimal(8,2), saletime timestamp)" \
	"copy users from '$S3/allusers_pipe.txt' $C delimiter '|'" \
	"copy venue from '$S3/venue_pipe.txt' $C delimiter '|'" \
	"copy category from '$S3/category_pipe.txt' $C delimiter '|'" \
	"copy date from '$S3/date2008_pipe.txt' $C delimiter '|'" \
	"copy event from '$S3/allevents_pipe.txt' $C delimiter '|' timeformat 'YYYY-MM-DD HH:MI:SS'" \
	"copy listing from '$S3/listings_pipe.txt' $C delimiter '|'" \
	"copy sales from '$S3/sales_tab.txt' $C delimiter '\t' timeformat 'MM/DD/YYYY HH:MI:SS'" \
	"grant select on all tables in schema public to public")
until [[ $(aws redshift-data describe-statement --id "$ID" --query Status --output text) =~ ^(FINISHED|FAILED|ABORTED)$ ]]; do sleep 5; done
aws redshift-data describe-statement --id "$ID" --query '[Status, Error]' --output text
