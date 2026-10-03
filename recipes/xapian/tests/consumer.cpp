#include <iostream>

#include <xapian.h>
int main()
{
        Xapian::WritableDatabase db("test-db", Xapian::DB_CREATE_OR_OVERWRITE);
        Xapian::Document doc;
        doc.set_data("notmuch foundation");
        doc.add_term("devkit");
        db.add_document(doc);
        db.commit();
        Xapian::Enquire query(db);
        query.set_query(Xapian::Query("devkit"));
        Xapian::MSet matches = query.get_mset(0, 10);
        if (matches.size() != 1)
                return 1;
        std::cout << matches.begin().get_document().get_data() << '\n';
        return matches.begin().get_document().get_data() !=
               "notmuch foundation";
}
