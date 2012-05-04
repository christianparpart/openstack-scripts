#! /bin/bash
# vim:ts=4:sw=4:noet
# ===========================================================================
# 
# This script seeds the OpenStack Keystone database with some initial data.
#
# Written by Christian Parpart (trapni)
#
# ===========================================================================

SWIFT=yes # shall we initialize SWIFT service into keystone?

PROJECT_TENANT_NAME="${PROJECT_TENANT_NAME:-Playground}"
PROJECT_TENANT_DESC="${PROJECT_TENANT_DESC:-Playground Tenant}"

ADMIN_USER_NAME="${ADMIN_USER_NAME:-admin}"
ADMIN_USER_PASS="${ADMIN_USER_PASS:-secret}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"

ADMIN_ROLE_NAME="admin"
MEMBER_ROLE_NAME="member"
RESELLER_ADMIN_ROLE_NAME="${RESELLER_ADMIN_ROLE_NAME:-ResellerAdmin}" # see swift-proxy.conf

REGION="${REGION:-RegionOne}"

# Service Tenant
SERVICE_TENANT_NAME="${SERVICE_TENANT_NAME:-service}"
SERVICE_TENANT_DESC="${SERVICE_TENANT_DESC:-Service Tenant}"

# Password for various services
SERVICE_PASS="${SERVICE_PASS:-secret}"

# Cloud Controller IP address
CC_IPADDR=${CC_IPADDR:-127.0.0.1}

# ---------------------------------------------------------------------------
# the 2 below are only used when seeding the keystone db
export SERVICE_TOKEN="${SERVICE_TOKEN:-admin}"
export SERVICE_ENDPOINT="${SERVICE_ENDPOINT:-http://localhost:35357/v2.0}"

# syntax: get_id KEYSTONE COMMAND LINE [...]
get_id() {
	echo `"$@" | awk '/ id / { print $4 }'`
}

# syntax: role_exists ROLE_NAME
role_exists() {
	local NAME="${1}"
	[[ $(keystone role-list | awk "/ ${NAME} / { print \$2 }") != "" ]]
}

# syntax: role_ensure ROLE_NAME
role_ensure() {
	local NAME="${1}"
	if role_exists "${NAME}"; then
		keystone role-list | awk "/ ${NAME} / {print \$2 }"
	else
		get_id keystone role-create --name "${NAME}"
	fi
}

notice() {
	echo -ne "\033[1;33m"
	echo " * $@"
	echo -ne "\033[0m"
}

keystone() {
	echo -e "\033[36mkeystone $@\033[0m" 1>&2
	$(which keystone) "$@"
}

# ---------------------------------------------------------------------------

notice "create roles (admin and member)"
ADMIN_ROLE_ID=$(get_id keystone role-create --name "${ADMIN_ROLE_NAME}")
MEMBER_ROLE_ID=$(get_id keystone role-create --name "${MEMBER_ROLE_NAME}")

notice "create the tenant(/project)"
PROJECT_TENANT_ID=$(get_id keystone tenant-create --name "${PROJECT_TENANT_NAME}" --description "${PROJECT_TENANT_DESC}" --enabled true)

notice "create an admin user"
ADMIN_USER_ID=$(get_id keystone user-create --enabled true \
	--name "${ADMIN_USER_NAME}" --pass "${ADMIN_USER_PASS}" \
	--email "${ADMIN_EMAIL}" --tenant_id "${PROJECT_TENANT_ID}")

notice "grant the admin user to be of admin-role in given tenant(/project)"
keystone user-role-add --user "${ADMIN_USER_ID}" --tenant_id "${PROJECT_TENANT_ID}" --role "${ADMIN_ROLE_ID}"

notice "create a service-tenant, containing all services"
SERVICE_TENANT_ID=$(get_id keystone tenant-create --name "${SERVICE_TENANT_NAME}" --description "${SERVICE_TENANT_DESC}" --enable true)

notice "reate glance-user and assign it to service-tenant as role admin"
GLANCE_UID=$(get_id keystone user-create --name glance --pass "${SERVICE_PASS}" --tenant_id "${SERVICE_TENANT_ID}" --enable true)
keystone user-role-add --tenant_id "${SERVICE_TENANT_ID}" --role "${ADMIN_ROLE_ID}" --user "${GLANCE_UID}"

notice "reate nova-user and assign it to service-tenant as role admin"
NOVA_UID=$(get_id keystone user-create --name nova --pass "${SERVICE_PASS}" --tenant_id "${SERVICE_TENANT_ID}" --enable true)
keystone user-role-add --tenant_id "${SERVICE_TENANT_ID}" --role "${ADMIN_ROLE_ID}" --user "${NOVA_UID}"

# notice "create ec2-user and assign it to service-tenant as role admin"
EC2_UID=$(get_id keystone user-create --name ec2 --pass "${SERVICE_PASS}" --tenant_id "${SERVICE_TENANT_ID}")
keystone user-role-add --tenant_id "${SERVICE_TENANT_ID}" --role "${ADMIN_ROLE_ID}" --user "${EC2_UID}"

# ---------------------------------------------------------------------------

notice "Creating services and their endpoints for region ${REGION} ..."

KEYSTONE_SERVICE_ID=$(get_id keystone service-create --name='keystone' --type='identity' --description='Keystone Identity Service')
keystone endpoint-create \
	--region "${REGION}" \
	--service_id=${KEYSTONE_SERVICE_ID} \
	--publicurl=http://${CC_IPADDR}:5000/v2.0 \
	--internalurl=http://${CC_IPADDR}:5000/v2.0 \
	--adminurl=http://${CC_IPADDR}:35357/v2.0

NOVACOMPUTE_SERVICE_ID=$(get_id keystone service-create --name='nova' --type='compute' --description='Nova Compute Service')
keystone endpoint-create \
	--region "${REGION}" \
	--service_id=${NOVACOMPUTE_SERVICE_ID} \
	--publicurl="http://${CC_IPADDR}:8774/v2/%(tenant_id)s" \
	--internalurl="http://${CC_IPADDR}:8774/v2/%(tenant_id)s" \
	--adminurl="http://${CC_IPADDR}:8774/v2/%(tenant_id)s"

VOLUME_SERVICE_ID=$(get_id keystone service-create --name='volume' --type='volume' --description="Nova Volume Service")
keystone endpoint-create \
	--region "${REGION}" \
	--service_id=${VOLUME_SERVICE_ID} \
	--publicurl="http://${CC_IPADDR}:8776/v1/%(tenant_id)s" \
	--internalurl="http://${CC_IPADDR}:8776/v1/%(tenant_id)s" \
	--adminurl="http://${CC_IPADDR}:8776/v1/%(tenant_id)s"

GLANCE_SERVICE_ID=$(get_id keystone service-create --name=glance --type=image --description="Glance Image Service")
keystone endpoint-create \
	--region "${REGION}" \
	--service_id=${GLANCE_SERVICE_ID} \
	--publicurl=http://${CC_IPADDR}:9292/v1 \
	--internalurl=http://${CC_IPADDR}:9292/v1 \
	--adminurl=http://${CC_IPADDR}:9292/v1

EC2_SERVICE_ID=$(get_id keystone service-create --name=ec2 --type=ec2 --description="EC2 Compatibility Layer")
keystone endpoint-create \
	--region "${REGION}" \
	--service_id=${EC2_SERVICE_ID} \
	--publicurl="http://${CC_IPADDR}:8773/services/Cloud" \
	--internalurl="http://${CC_IPADDR}:8773/services/Cloud" \
	--adminurl="http://${CC_IPADDR}:8773/services/Admin"

# -----------------------------------------------------------------------------

if [[ "${SWIFT}" == "yes" ]]; then
	notice "create swift-user and assign it to service-tenant as role admin"
	SWIFT_UID=$(get_id keystone user-create --name swift --pass "${SERVICE_PASS}" --tenant_id "${SERVICE_TENANT_ID}" --enable true)
	keystone user-role-add --tenant_id "${SERVICE_TENANT_ID}" --role "${ADMIN_ROLE_ID}" --user "${SWIFT_UID}"

	RESELLER_ROLE_ID=$(get_id keystone role-create --name "${RESELLER_ADMIN_ROLE_NAME}")
	keystone user-role-add --tenant_id "${SERVICE_TENANT_ID}" --role "${RESELLER_ROLE_ID}" --user "${NOVA_UID}"

	SWIFT_SERVICE_ID=$(get_id keystone service-create --name='swift' --type='storage' --description="Object Storage Service")
	keystone endpoint-create \
		--region "${REGION}" \
		--service_id=${SWIFT_SERVICE_ID} \
		--publicurl "http://${CC_IPADDR}:8080/v1/AUTH_\$(tenant_id)s" \
		--adminurl "http://${CC_IPADDR}:8080/" \
		--internalurl "http://${CC_IPADDR}:8080/v1/AUTH_\$(tenant_id)s"
fi

notice "Done."
