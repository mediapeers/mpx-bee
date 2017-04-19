_         = require('lodash')
archiver  = require('archiver')
AWS       = require('aws-promised')
optparse  = require('optparse')
util      = require('util')
fs        = require('fs')
glob      = require('glob')
path      = require('path')
Promise   = require('bluebird')
MIM       = require('mim')

printLine = (line) -> process.stdout.write line + '\n'
printWarn = (line) -> process.stderr.write line + '\n'

SWITCHES = [
  ['-i', '--input PATH',      'source folder'],
  ['-f', '--filename FILE',   'zip filename'],
  ['-b', '--bucket NAME',     'S3 bucket name'],
  ['-t', '--target NAME',     "S3 key prefix (e.g. 'deploy/2015-04-01/'"],
  ['-n', '--nozip',           'disables zipping'],
  ['-a', '--archive',         'enables backup instead of overwriting'],
  ['-h', '--help',            'display this help message']
]

TMPDIR = 'tmp'
BACKUP_PREFIX = 'backup'

opts =
  backup: false
  zip: true
  zipfile: "#{TMPDIR}/archive.zip"
  targetDir: undefined
  bucket: undefined
  source: undefined

s3 = AWS.s3()

exports.run = ->
  # read command line arguments
  parser = new optparse.OptionParser(SWITCHES)

  parser.on 'help', ->
    printLine parser.toString()
    process.exit()

  parser.on 'input', (name, value) ->
    opts.source = value

  parser.on 'filename', (name, value) ->
    opts.zipfile = path.join(TMPDIR, value)

  parser.on 'bucket', (name, value) ->
    opts.bucket = value

  parser.on 'target', (name, value) ->
    opts.targetDir = value

  parser.on 'nozip', ->
    opts.zip = false

  parser.on 'archive', ->
    opts.backup = true

  parser.parse(process.argv[2..])

  missingArgs = _.any ['bucket', 'source'], (arg) ->
    _.isEmpty(opts[arg])

  if missingArgs
    printLine 'REQUIRED ARGUMENTS MISSING!'
    printLine ''
    printLine parser.toString()
    process.exit()

  fs.mkdirSync(TMPDIR) unless fs.existsSync(TMPDIR)

  processFiles = ->
    if opts.backup
      backupFiles().then uploadFiles
    else
      keyPrefix = path.join(opts.targetDir, '/')
      clearFiles(keyPrefix).then uploadFiles

  if opts.zip
    createZip().then processFiles
  else
    readFiles()
    processFiles()


createZip = ->
  new Promise (resolve, reject) ->
    # create zip
    archive = archiver('zip')
    output  = fs.createWriteStream(opts.zipfile)

    archive.pipe(output)
    archive.bulk([
      src: ["**/*"],
      expand: true,
      cwd: opts.source,
      dot: true
    ])
    archive.on 'finish', -> resolve()
    archive.on 'error', -> reject()

    archive.finalize()

    opts.source = path.dirname(opts.zipfile)
    opts.files = [opts.zipfile]

readFiles = ->
  opts.files = glob.sync(
    path.join(opts.source, "**/*"),
    expand: true,
    dot: true,
    nodir: true
  )

backupFiles = ->
  new Promise (resolve, reject) ->
    keyPrefix       = path.join(opts.targetDir, '/')
    backupKeyPrefix = path.join(BACKUP_PREFIX, opts.targetDir, '/')

    clearFiles(backupKeyPrefix).then ->
      readExistingFiles(keyPrefix).then (keys) ->
        return resolve() if _.isEmpty(keys)

        process.stdout.write 'Backup'

        promises = []
        for key in keys
          promise = s3.copyObjectPromised({
            Bucket: opts.bucket,
            CopySource: "#{opts.bucket}/#{key}",
            Key: path.join(BACKUP_PREFIX, key),
            ACL: 'public-read'
          })
          promise.then -> process.stdout.write '.'
          promises.push promise

        Promise.all(promises).then ->
          process.stdout.write ' - done!\n'
          keyPrefix = path.join(opts.targetDir, '/')
          clearFiles(keyPrefix).then -> resolve()

clearFiles = (pathPrefix) ->
  new Promise (resolve, reject) ->
    readExistingFiles(pathPrefix).then (keys) ->
      return resolve() if _.isEmpty(keys)

      process.stdout.write 'Cleanup'

      objects = _.map keys, (key) -> { Key: key }

      s3.deleteObjectsPromised({
        Bucket: opts.bucket,
        Delete: { Objects: objects }
      })
      .then ->
        process.stdout.write ' - done!\n'
        resolve()

readExistingFiles = (keyPrefix) ->
  new Promise (resolve, reject) ->
    onSuccess = (data) ->
      keys = _.map data['Contents'], 'Key'
      resolve(keys)

    promise = s3.listObjectsPromised({
      Bucket: opts.bucket,
      Prefix: keyPrefix
    }).then onSuccess

uploadFiles = ->
  promises = []

  process.stdout.write 'Uploading'
  for file in opts.files
    targetFile = file.replace path.join(opts.source, '/'), ''
    targetKey  = path.join opts.targetDir, targetFile

    params =
      Bucket: opts.bucket,
      Key: targetKey,
      Body: fs.createReadStream(file),
      ACL: 'public-read',

    if mime = MIM.getMIMEType(file)
      params['ContentType'] = MIM.getMIMEType(file)

    promise = s3.putObjectPromised(params)

    onSuccess = ->
      process.stdout.write '.'

    onError = (error) ->
      printLine util.inspect(error)
      process.exit()

    promise.then onSuccess, onError
    promises.push promise

  Promise.all(promises).then ->
    process.stdout.write ' - done!\n'
