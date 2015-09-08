# mpx-bee
npm module to zip (optional) local static files and deposit them on AWS S3 (collect the honey)

__NOTE:__ due to limitations of the aws node sdk mpx-bee currently only works with a file count <= 1000

##  setup
install via `npm install -g mpx-bee`

make sure you have configured AWS credentials as described here: [AWS Docs](http://docs.aws.amazon.com/AWSJavaScriptSDK/guide/node-configuring.html)

## usage

```
Usage: [Options]

Available options:
  -i, --input PATH      source folder
  -f, --filename FILE   zip filename
  -b, --bucket NAME     S3 bucket name
  -t, --target NAME     S3 key prefix (e.g. 'deploy/2015-04-01/'
  -n, --nozip           disables zipping
  -a, --archive         enables backup instead of overwriting
  -h, --help            display this help message
```

### examples:

1.
```
mpx-bee --input dist_folder --target '2015-09-08' --bucket 'your-bucket-name' --nozip --archive
```

this will
* S3: check for files in 'backup/2015-09-08' and delete them
* S3: move all files (if any) from '2015-09-08' to 'backup/2015-09-08'
* upload all files from your local folder `dist_folder` to S3 into with the key prefix '2015-09-08'

2.
```
mpx-bee --input dist_folder --target '2015-09-08' --bucket 'your-bucket-name' --filename release.zip
```

this will
* S3: check for files in '2015-09-08' and delete them
* zip all files from your local folder 'dist_folder' into a zip with the filename 'release.zip'
* upload the zip to S3 with the key '2015-09-08/release.zip'