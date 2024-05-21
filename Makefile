include .env

deploy:
		forge script script/GnosisPayInfraDeployment.s.sol \
		--rpc-url ${GNOSIS_RPC_URL} \
		--broadcast \
		--legacy \
		-vvvv 

deployAnvil:
		forge script script/GnosisPayInfraDeployment.s.sol \
		--rpc-url http://127.0.0.1:8545 \
		--broadcast \
		--legacy \
		-vvvv 

startAnvil:
	anvil \
	--code-size-limit 1000000 \
	--fork-url ${GNOSIS_RPC_URL} \
	--gas-price 0
