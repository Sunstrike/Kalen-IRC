# Build start
system('curl -X POST --data "payload={\"project\": \"Tinkers Construct\", \"build\": \"42\"}" 127.0.0.1:9090/build-start')

# Build failed
system('curl -X POST --data "payload={\"project\": \"Tinkers Construct\", \"build\": \"42\"}" 127.0.0.1:9090/build-fail')

# Finish/deploy
system('curl -X POST --data "payload={\"project\": \"Tinkers Construct\", \"channel\": \"Development\", \"version\": \"1.4.7d4\", \"url\": \"http://tanis.sunstrike.io/TConstruct/development/TConstruct_1.6.4_1.4.7d4.jar\", \"buildkey\": \"TIC-AP-82\"}" 127.0.0.1:9090/build')
