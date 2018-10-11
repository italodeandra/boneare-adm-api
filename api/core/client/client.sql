/**/


SELECT DeleteFunctions('BoneareAdm', 'ClientFindAll');
CREATE OR REPLACE FUNCTION BoneareAdm.ClientFindAll(
    pFilter     VARCHAR(200),
    pSortColumn VARCHAR(100),
    pSortOrder  VARCHAR(100),
    pPageNumber INTEGER,
    pPageSize   INTEGER
)
    RETURNS TABLE(
        "lineCount" BIGINT,
        "id"        BoneareAdm.Client.id%TYPE,
        "name"      BoneareAdm.Client.name%TYPE
    ) AS $$

/*
Documentation
Source file.......: client.sql
Description.......: Find all clients
Author............: Ítalo Andrade
Date..............: 12/09/2018
Ex................:

SELECT * FROM BoneareAdm.ClientFindAll(null, null, null, 1, 10);

*/

BEGIN
    RETURN QUERY
    SELECT COUNT(1) OVER (PARTITION BY 1) lineCount, c.id, c.name
    FROM BoneareAdm.Client c
    WHERE CASE
              WHEN pFilter IS NOT NULL
                    THEN unaccent(c.name) ILIKE '%' || unaccent(pFilter) || '%' OR
                         c.id :: TEXT = pFilter
              ELSE TRUE END
    ORDER BY (iif(pSortColumn = 'id' AND pSortOrder = 'asc', c.id, NULL)) ASC,
             (iif(pSortColumn = 'id' AND pSortOrder = 'desc', c.id, NULL)) DESC,
             (iif(pSortColumn = 'name' AND pSortOrder = 'asc', c.name, NULL)) ASC,
             (iif(pSortColumn = 'name' AND pSortOrder = 'desc', c.name, NULL)) DESC,
             (COALESCE(c.last_update_date, c.creation_date)) DESC
    LIMIT iif(pPageSize > 0 AND pPageNumber >= 0, pPageSize, NULL)
    OFFSET iif(pPageSize > 0 AND pPageNumber >= 0, pPageNumber * pPageSize, NULL);
END;
$$
LANGUAGE plpgsql;


SELECT DeleteFunctions('BoneareAdm', 'ClientAdd');
CREATE OR REPLACE FUNCTION BoneareAdm.ClientAdd(
    pUserIdAction BoneareAdm.User.id%TYPE,
    pName         BoneareAdm.Client.name%TYPE,
    pDocument     BoneareAdm.Client.document%TYPE,
    pDescription  BoneareAdm.Client.description%TYPE
)
    RETURNS JSON AS $$

/*
Documentation
Source file.......: client.sql
Description.......: Add a new client
Author............: Ítalo Andrade
Date..............: 10/10/2018
Ex................:

SELECT * FROM BoneareAdm.ClientAdd(
   1,               -- pUserIdAction
   'Client Test',   -- pName
   '45338491800'    -- pDocument,
   null             -- pDescription
);

*/

DECLARE
    vErrorProcedure TEXT;
    vErrorMessage   TEXT;
    vId             BoneareAdm.Client.id%TYPE;

BEGIN
    IF EXISTS(SELECT 1 FROM BoneareAdm.Client c WHERE c.document = pDocument)
    THEN
        RETURN
        json_build_object(
            'code', 1,
            'message', 'Documento existente'
        );
    END IF;

    INSERT INTO BoneareAdm.Client (name, document, description, created_by)
    VALUES (pName, pDocument, pDescription, pUserIdAction)
        RETURNING id
            INTO vId;

    RETURN
    json_build_object(
        'code', 0,
        'return', json_build_object(
            'id', vId
        )
    );
    EXCEPTION WHEN OTHERS
    THEN
        GET STACKED DIAGNOSTICS vErrorProcedure = MESSAGE_TEXT;
        GET STACKED DIAGNOSTICS vErrorMessage = PG_EXCEPTION_CONTEXT;
        RAISE EXCEPTION 'Internal Error: (%) %', vErrorProcedure, vErrorMessage;
END;
$$
LANGUAGE plpgsql;


SELECT DeleteFunctions('BoneareAdm', 'ClientUpdate');
CREATE OR REPLACE FUNCTION BoneareAdm.ClientUpdate(
    pUserIdAction BoneareAdm.User.id%TYPE,
    pId           BoneareAdm.Client.id%TYPE,
    pName         BoneareAdm.Client.name%TYPE,
    pDocument     BoneareAdm.Client.document%TYPE,
    pDescription  BoneareAdm.Client.description%TYPE
)
    RETURNS JSON AS $$

/*
Documentation
Source file.......: client.sql
Description.......: Update a client
Author............: Ítalo Andrade
Date..............: 10/10/2018
Ex................:

SELECT * FROM BoneareAdm.ClientUpdate(
   1,               -- pUserIdAction
   12,              -- pId
   'Client Test',   -- pName
   '45338491800'    -- pDocument,
   null             -- pDescription
);

*/

DECLARE
    vErrorProcedure TEXT;
    vErrorMessage   TEXT;

BEGIN
    IF NOT EXISTS(SELECT 1 FROM BoneareAdm.Client c WHERE c.id = pId)
    THEN
        RETURN
        json_build_object(
            'code', 1,
            'message', 'Cliente não encontrado'
        );
    END IF;

    IF EXISTS(SELECT 1 FROM BoneareAdm.Client c WHERE c.document = pDocument
                                                  AND c.id <> pId)
    THEN
        RETURN
        json_build_object(
            'code', 2,
            'message', 'Documento existente'
        );
    END IF;

    UPDATE BoneareAdm.Client
    SET name             = pName,
        document         = pDocument,
        description      = pDescription,
        last_updated_by  = pUserIdAction,
        last_update_date = CURRENT_TIMESTAMP
    WHERE id = pId;

    RETURN
    json_build_object(
        'code', 0
    );
    EXCEPTION WHEN OTHERS
    THEN
        GET STACKED DIAGNOSTICS vErrorProcedure = MESSAGE_TEXT;
        GET STACKED DIAGNOSTICS vErrorMessage = PG_EXCEPTION_CONTEXT;
        RAISE EXCEPTION 'Internal Error: (%) %', vErrorProcedure, vErrorMessage;
END;
$$
LANGUAGE plpgsql;


SELECT DeleteFunctions('BoneareAdm', 'ClientRemove');
CREATE OR REPLACE FUNCTION BoneareAdm.ClientRemove(
    pId BoneareAdm.Client.id%TYPE
)
    RETURNS JSONB AS $$

/*
Documentation
Source file.......: client.sql
Description.......: Remove a client
Author............: Ítalo Andrade
Date..............: 10/10/2018
Ex................:

SELECT * FROM BoneareAdm.ClientRemove(
   13   -- pId
);

*/

DECLARE
    vErrorProcedure TEXT;
    vErrorMessage   TEXT;
    vRelations      JSONB = '[]';
    vNewRelation    JSONB;

BEGIN
    IF NOT EXISTS(SELECT 1 FROM BoneareAdm.Client c WHERE c.id = pId)
    THEN
        RETURN
        jsonb_build_object(
            'code', 1,
            'message', 'Cliente não encontrado'
        );
    END IF;

    SELECT to_jsonb(o) INTO vNewRelation FROM BoneareAdm.Order o WHERE o.client_id = pId;
    IF vNewRelation IS NOT NULL
    THEN
        vRelations = vRelations || jsonb_build_object(
            'relation', 'Pedido ' || (vNewRelation ->> 'description'),
            'url', '/order/' || (vNewRelation ->> 'id')
        );
    END IF;

    IF jsonb_array_length(vRelations) > 0
    THEN
        RETURN
        jsonb_build_object(
            'code', 2,
            'message', 'Contém vínculos',
            'relations', vRelations
        );
    END IF;

    DELETE FROM BoneareAdm.Client_Address WHERE client_id = pId;
    DELETE FROM BoneareAdm.Client WHERE id = pId;

    RETURN
    jsonb_build_object(
        'code', 0
    );
    EXCEPTION WHEN OTHERS
    THEN
        GET STACKED DIAGNOSTICS vErrorProcedure = MESSAGE_TEXT;
        GET STACKED DIAGNOSTICS vErrorMessage = PG_EXCEPTION_CONTEXT;
        RAISE EXCEPTION 'Internal Error: (%) %', vErrorProcedure, vErrorMessage;
END;
$$
LANGUAGE plpgsql;


/**/