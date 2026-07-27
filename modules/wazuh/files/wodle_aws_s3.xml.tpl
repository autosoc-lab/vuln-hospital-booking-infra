  <wodle name="aws-s3">
    <disabled>no</disabled>
    <interval>10m</interval>
    <run_on_start>yes</run_on_start>
    <bucket type="cloudtrail">
      <name>${log_bucket_name}</name>
    </bucket>
    <bucket type="vpcflow">
      <name>${log_bucket_name}</name>
    </bucket>
    <bucket type="guardduty">
      <name>${log_bucket_name}</name>
      <path>guardduty</path>
    </bucket>
  </wodle>
