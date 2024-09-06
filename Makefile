# -*- Makefile -*-

-include $(buildTop)/share/dws/prefix.mk

srcDir        ?= .
installTop    ?= $(VIRTUAL_ENV)
binDir        ?= $(installTop)/bin
libDir        ?= $(installTop)/lib
CONFIG_DIR    ?= $(srcDir)
# XXX CONFIG_DIR should really be $(installTop)/etc/testsite
LOCALSTATEDIR ?= $(installTop)/var

installDirs   ?= install -d
installFiles  ?= install -p -m 644
NPM           ?= npm
PYTHON        := python
PIP           := pip
SQLITE        := sqlite3
TWINE         := twine

RUN_DIR       ?= $(abspath $(srcDir))
DB_NAME       ?= $(RUN_DIR)/db.sqlite

$(info Path to python executable (i.e. PYTHON) while running make: $(shell which $(PYTHON)))

MANAGE        := TESTSITE_SETTINGS_LOCATION=$(CONFIG_DIR) RUN_DIR=$(RUN_DIR) $(PYTHON) manage.py

# Django 1.7,1.8 sync tables without migrations by default while Django 1.9
# requires a --run-syncdb argument.
# Implementation Note: We have to wait for the config files to be installed
# before running the manage.py command (else missing SECRECT_KEY).
RUNSYNCDB     = $(if $(findstring --run-syncdb,$(shell cd $(srcDir) && $(MANAGE) migrate --help 2>/dev/null)),--run-syncdb,)


install::
	cd $(srcDir) && $(PIP) install .


install-conf:: $(DESTDIR)$(CONFIG_DIR)/credentials \
                $(DESTDIR)$(CONFIG_DIR)/gunicorn.conf


dist::
	$(PYTHON) -m build
	$(TWINE) check dist/*
	$(TWINE) upload dist/*


build-assets: vendor-assets-prerequisites


clean:: clean-dbs
	[ ! -f $(srcDir)/package-lock.json ] || rm $(srcDir)/package-lock.json
	find $(srcDir) -name '__pycache__' -exec rm -rf {} +
	find $(srcDir) -name '*~' -exec rm -rf {} +

clean-dbs:
	[ ! -f $(DB_NAME) ] || rm $(DB_NAME)


initdb-with-dummydata: initdb
	cd $(srcDir) && $(MANAGE) load_test_transactions


initdb: clean-dbs
	$(installDirs) $(dir $(DB_NAME))
	cd $(srcDir) && $(MANAGE) migrate $(RUNSYNCDB) --noinput
	echo "CREATE UNIQUE INDEX uniq_email ON auth_user(email);" | $(SQLITE) $(DB_NAME)
	cd $(srcDir) && $(MANAGE) loaddata \
        testsite/fixtures/initial_data.json \
        testsite/fixtures/test_data.json \
        testsite/fixtures/50-visit-card2.json \
        testsite/fixtures/100-balance-due.json \
        testsite/fixtures/110-balance-checkout.json \
        testsite/fixtures/120-subscriptions.json \
        testsite/fixtures/130-subscriptions.json \
        testsite/fixtures/140-payment-gap.json \
        testsite/fixtures/150-subscribers.json


doc:
	$(installDirs) build/docs
	cd $(srcDir) && sphinx-build -b html ./docs $(PWD)/build/docs


vendor-assets-prerequisites: $(libDir)/.npm/djaodjin-saas-packages


$(DESTDIR)$(CONFIG_DIR)/credentials: $(srcDir)/testsite/etc/credentials
	$(installDirs) $(dir $@)
	@if [ ! -f $@ ] ; then \
		sed \
		-e "s,\%(SECRET_KEY)s,`$(PYTHON) -c 'import sys ; from random import choice ; sys.stdout.write("".join([choice("abcdefghijklmnopqrstuvwxyz0123456789!@#$%^*-_=+") for i in range(50)]))'`," \
		-e "s,STRIPE_PUB_KEY = \"\",STRIPE_PUB_KEY = \"$(STRIPE_PUB_KEY)\"," \
		-e "s,STRIPE_PRIV_KEY = \"\",STRIPE_PRIV_KEY = \"$(STRIPE_PRIV_KEY)\","\
		-e "s,STRIPE_CLIENT_ID = \"\",STRIPE_CLIENT_ID = \"$(STRIPE_CLIENT_ID)\","\
			$< > $@ ; \
	else \
		echo "warning: We are keeping $@ intact but $< contains updates that might affect behavior of the testsite." ; \
	fi


$(DESTDIR)$(CONFIG_DIR)/gunicorn.conf: $(srcDir)/testsite/etc/gunicorn.conf
	$(installDirs) $(dir $@)
	[ -f $@ ] || sed \
		-e 's,%(LOCALSTATEDIR)s,$(LOCALSTATEDIR),' \
		-e 's,%(RUN_DIR)s,$(RUN_DIR),' $< > $@


$(libDir)/.npm/djaodjin-saas-packages: $(srcDir)/testsite/package.json
	$(installFiles) $^ $(libDir)
	$(NPM) install --loglevel verbose --cache $(libDir)/.npm --prefix $(libDir)
	$(installDirs) -d $(srcDir)/testsite/static/vendor
	$(installFiles) $(libDir)/node_modules/jquery/dist/jquery.js $(srcDir)/testsite/static/vendor
	$(installFiles) $(libDir)/node_modules/moment/moment.js $(srcDir)/testsite/static/vendor
	$(installFiles) $(libDir)/node_modules/moment-timezone/builds/moment-timezone-with-data.js $(srcDir)/testsite/static/vendor
	$(installFiles) $(libDir)/node_modules/vue/dist/vue.js $(srcDir)/testsite/static/vendor
	$(installFiles) $(libDir)/node_modules/vue-croppa/dist/vue-croppa.js $(srcDir)/testsite/static/vendor
	touch $@


.PHONY: all check dist doc install
